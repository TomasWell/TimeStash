import Foundation
import Combine
import SwiftUI

/// The single source of truth for everything on screen.
@MainActor
final class VaultStore: ObservableObject {

    @Published private(set) var tasks: [VaultTask] = []
    @Published private(set) var totalSavedSeconds: Int = 0
    @Published private(set) var todaySavedSeconds: Int = 0
    @Published private(set) var savedByCategory: [VaultCategory: Int] = [:]
    @Published private(set) var runningTask: VaultTask?
    @Published private(set) var pausedTask: VaultTask?
    @Published private(set) var elapsedSeconds: Int = 0
    /// The task that just went into the vault, used to fire the celebration.
    @Published var lastDeposit: VaultTask?
    /// A task that was still running when the app was killed. The home
    /// screen asks the user whether to keep going.
    @Published private(set) var recoverableTask: VaultTask?

    /// 巡检路由 `resume` 用：把当前 running 任务摆成「上次没关就退了」的现场。
    /// 生产代码不调用（detectRecoverableTask 只在冷启动问一次）。
    func debugMakeRecoverable() {
        if let running = runningTask {
            recoverableTask = running
        }
    }

    /// The user's own idea of how long a typical task takes — set on the
    /// last onboarding screen, used as the default estimate from then on.
    @AppStorage("baselineEstimateSeconds") var baselineEstimateSeconds: Int = 30 * 60

    private let repository: VaultRepository
    private var ticker: Timer?
    /// Whether the "still working on it?" question has already been asked
    /// this launch.
    private var hasAskedAboutRecovery = false

    init(repository: VaultRepository = VaultRepository()) {
        self.repository = repository
    }

    // MARK: - Loading

    func refresh() {
        tasks = (try? repository.allTasks()) ?? []
        totalSavedSeconds = (try? repository.totalSavedSeconds()) ?? 0
        let startOfDay = Calendar.current.startOfDay(for: Date())
        todaySavedSeconds = (try? repository.savedSeconds(since: startOfDay)) ?? 0
        savedByCategory = (try? repository.savedSecondsByCategory()) ?? [:]
        runningTask = try? repository.runningTask()
        pausedTask = try? repository.pausedTask()
        updateElapsed()
        if runningTask != nil { startTicker() } else { stopTicker() }
    }

    /// Looks for a task that was still running when the app was killed.
    ///
    /// Called once at launch. The timer keeps counting while the app is
    /// closed, so the user is asked whether they are still working on it
    /// instead of silently finding a running clock.
    func detectRecoverableTask() {
        // 一条启动线索只问一次：用户答过之后回到前台，不该再被问一遍。
        guard recoverableTask == nil, !hasAskedAboutRecovery else { return }
        hasAskedAboutRecovery = true
        guard let running = try? repository.runningTask() else { return }
        recoverableTask = running
    }

    /// Dismiss the "still working on it?" question without touching the task.
    func keepRecoverableTaskRunning() {
        recoverableTask = nil
        refresh()
    }

    /// Close out the recovered task: whatever it earned is banked, and the
    /// user is not nagged about it again.
    func finishRecoverableTask() {
        guard let task = recoverableTask, let id = task.id else {
            recoverableTask = nil
            return
        }
        let elapsed = task.elapsedSeconds()
        _ = try? repository.finishTask(id: id, actualSeconds: elapsed)
        VaultNotifier.cancelReminders(taskID: id)
        recoverableTask = nil
        refresh()
    }

    // MARK: - Actions

    @discardableResult
    func createTask(title: String, category: VaultCategory, estimatedSeconds: Int) -> VaultTask? {
        guard let task = try? repository.createTask(
            title: title,
            category: category,
            estimatedSeconds: estimatedSeconds
        ) else { return nil }
        refresh()
        return task
    }

    /// Create a task and immediately start its timer.
    ///
    /// Used by the onboarding one-minute experiment, which must not pollute
    /// the per-category calibration samples — a 60-second demo is not
    /// evidence about how long the user takes to write a report.
    @discardableResult
    func createSampleTask(title: String, category: VaultCategory, estimatedSeconds: Int) -> VaultTask? {
        guard let task = try? repository.createTask(
            title: title,
            category: category,
            estimatedSeconds: estimatedSeconds,
            isSample: true
        ) else { return nil }
        refresh()
        return task
    }

    func start(taskID: Int64) {
        guard let task = try? repository.startTask(id: taskID) else { return }
        refresh()
        // Ask for notification permission the first time a real timer runs —
        // a prompt with no context is the fastest way to get denied.
        Task { await VaultNotifier.requestPermissionIfNeeded() }
        VaultNotifier.scheduleReminders(taskID: taskID, estimatedSeconds: task.estimatedSeconds)
    }

    /// Pause the timer. The time spent so far is banked, so a pause never
    /// counts against the estimate.
    func pause(taskID: Int64) {
        _ = try? repository.pauseTask(id: taskID)
        VaultNotifier.cancelReminders(taskID: taskID)
        refresh()
    }

    /// Finish the running task. Returns the seconds that went into the vault.
    @discardableResult
    func finish(taskID: Int64) -> Int {
        let actual = elapsedSeconds(for: taskID)
        guard let finished = try? repository.finishTask(id: taskID, actualSeconds: actual) else {
            return 0
        }
        VaultNotifier.cancelReminders(taskID: taskID)
        lastDeposit = finished.savedSeconds > 0 ? finished : nil
        refresh()
        return finished.savedSeconds
    }

    func abandon(taskID: Int64) {
        _ = try? repository.abandonTask(id: taskID, actualSeconds: elapsedSeconds(for: taskID))
        VaultNotifier.cancelReminders(taskID: taskID)
        refresh()
    }

    func delete(taskID: Int64) {
        guard (try? repository.deleteTask(id: taskID)) != nil else { return }
        refresh()
    }

    // MARK: - Derived values

    /// The task the timer screen is showing: the running one, or the paused
    /// one when the user paused it.
    var activeTask: VaultTask? {
        runningTask ?? pausedTask
    }

    /// How long a specific task has been going.
    ///
    /// ⚠️ 必须**按任务算**，不能用 store 上的一个全局值：
    /// 暂停 A、再开始 B 之后，A 和 B 同时存在，
    /// 全局值反映的是 B —— 计时界面却显示 A → 显示的时长是别的任务的
    /// （2026-11-07 实测：暂停后时钟反而在走，就是这个原因）。
    func elapsedSeconds(for taskID: Int64) -> Int {
        tasks.first { $0.id == taskID }?.elapsedSeconds() ?? 0
    }

    /// The estimate the user should start with, already adjusted by what
    /// history says about their category.
    func suggestedEstimate(for category: VaultCategory) -> Int {
        let samples = (try? repository.calibrationSample(category: category)) ?? []
        guard let factor = VaultMath.calibrationFactor(tasks: samples) else {
            return baselineEstimateSeconds
        }
        return max(60, Int((Double(baselineEstimateSeconds) * factor).rounded()))
    }

    func calibrationAdvice(category: VaultCategory? = nil) -> String? {
        let samples = (try? repository.calibrationSample(category: category)) ?? []
        return VaultMath.calibrationAdvice(tasks: samples, category: category)
    }

    func dailySeries(days: Int) -> [(day: Date, seconds: Int)] {
        (try? repository.dailySavedSeries(days: days)) ?? []
    }

    var milestones: (earned: [VaultMilestone], next: VaultMilestone?) {
        VaultMilestone.progress(totalSeconds: totalSavedSeconds)
    }

    /// How full the box is inside the current milestone band.
    var boxFill: (filled: Int, target: Int) {
        VaultMilestone.band(totalSeconds: totalSavedSeconds)
    }

    // MARK: - Ticker

    private func updateElapsed() {
        // Uses the task's own accumulator so a pause (or an app kill) keeps
        // the time already spent.
        elapsedSeconds = activeTask?.elapsedSeconds() ?? 0
    }

    private func startTicker() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateElapsed()
            }
        }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }
}
