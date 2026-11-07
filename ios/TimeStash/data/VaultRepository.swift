import Foundation
import GRDB

/// Every read and write against the vault goes through here.
///
/// The repository owns the rules that must not be bypassed:
/// the estimate locks when the timer starts, and only the timer path can
/// credit time to the vault.
struct VaultRepository: Sendable {

    let db: AppDatabase

    init(db: AppDatabase = .shared) {
        self.db = db
    }

    // MARK: - Writing

    /// Create a task that has not started yet.
    func createTask(
        title: String,
        category: VaultCategory,
        estimatedSeconds: Int,
        isSample: Bool = false
    ) throws -> VaultTask {
        var task = VaultTask(
            title: title,
            category: category,
            estimatedSeconds: VaultMath.lockedEstimate(estimatedSeconds),
            isSample: isSample
        )
        try db.dbQueue.write { db in
            // GRDB 7 的 insert 不返回行号对象（`inserted.rowID` 编译不过），
            // 而 `didInsert` 回调在 PersistableRecord 的非 mutating 插入路径上
            // 拿到的是副本，写不回外层变量 —— 所以直接从连接上取最后插入的行号。
            try task.insert(db)
            task.id = db.lastInsertedRowID
        }
        return task
    }

    /// Start the timer. The estimate is frozen at this moment — from here on
    /// the task can only be renamed, never re-estimated.
    @discardableResult
    func startTask(id: Int64, at date: Date = Date()) throws -> VaultTask {
        try db.dbQueue.write { db in
            guard var task = try VaultTask.fetchOne(db, key: id) else {
                throw VaultRepositoryError.taskNotFound
            }
            guard task.state == .planned || task.state == .paused else {
                throw VaultRepositoryError.alreadyRunning
            }
            // 同一时间只能有一个任务在走表。
            // 之前没管这件事 → 上一个会话遗留的「运行中」任务和新任务并存
            // → `runningTask()` 按 startedAt 倒序只返回其中一个
            // → 计时界面显示的是**另一个任务**的时长（2026-11-07 实测：
            // 暂停后时钟反而在走，因为读的是那个遗留任务的时长）。
            // 修法：开始新任务时，把还在走的那个**暂停**（已用时长不丢）。
            if let other = try VaultTask
                .filter(VaultTask.Columns.stateRaw == VaultTaskState.running.rawValue)
                .filter(VaultTask.Columns.id != id)
                .fetchOne(db) {
                var pausedOther = other
                if let startedAt = pausedOther.startedAt {
                    pausedOther.accumulatedSeconds += max(0, Int(date.timeIntervalSince(startedAt)))
                }
                pausedOther.startedAt = nil
                pausedOther.stateRaw = VaultTaskState.paused.rawValue
                try pausedOther.update(db)
            }
            task.stateRaw = VaultTaskState.running.rawValue
            task.startedAt = date
            task.estimatedSeconds = VaultMath.lockedEstimate(task.estimatedSeconds)
            try task.update(db)
            return task
        }
    }

    /// Pause the timer. The time spent so far is banked into
    /// `accumulatedSeconds` so a pause never counts against the estimate.
    @discardableResult
    func pauseTask(id: Int64, at date: Date = Date()) throws -> VaultTask {
        try db.dbQueue.write { db in
            guard var task = try VaultTask.fetchOne(db, key: id) else {
                throw VaultRepositoryError.taskNotFound
            }
            guard task.state == .running, let startedAt = task.startedAt else {
                throw VaultRepositoryError.notRunning
            }
            task.accumulatedSeconds += max(0, Int(date.timeIntervalSince(startedAt)))
            task.startedAt = nil
            task.stateRaw = VaultTaskState.paused.rawValue
            try task.update(db)
            return task
        }
    }

    /// Finish the task early (or late) and credit whatever it earned.
    ///
    /// Finishing over the estimate is not a failure — it is recorded, it
    /// just doesn't put anything in the vault.
    @discardableResult
    func finishTask(id: Int64, actualSeconds: Int, at date: Date = Date()) throws -> VaultTask {
        try db.dbQueue.write { db in
            guard var task = try VaultTask.fetchOne(db, key: id) else {
                throw VaultRepositoryError.taskNotFound
            }
            guard task.state == .running || task.state == .paused else {
                throw VaultRepositoryError.notRunning
            }
            let elapsed = max(0, actualSeconds)
            task.actualSeconds = elapsed
            task.accumulatedSeconds = elapsed
            task.startedAt = nil
            task.finishedAt = date
            task.stateRaw = VaultTaskState.finished.rawValue
            task.savedSeconds = VaultMath.savedSeconds(
                estimatedSeconds: task.estimatedSeconds,
                actualSeconds: elapsed
            )
            try task.update(db)
            return task
        }
    }

    /// Give up on a task. It stays in the ledger for the record, but it never
    /// credits the vault.
    @discardableResult
    func abandonTask(id: Int64, actualSeconds: Int? = nil, at date: Date = Date()) throws -> VaultTask {
        try db.dbQueue.write { db in
            guard var task = try VaultTask.fetchOne(db, key: id) else {
                throw VaultRepositoryError.taskNotFound
            }
            task.actualSeconds = actualSeconds
            task.accumulatedSeconds = actualSeconds ?? task.accumulatedSeconds
            task.startedAt = nil
            task.finishedAt = date
            task.stateRaw = VaultTaskState.abandoned.rawValue
            task.savedSeconds = 0
            try task.update(db)
            return task
        }
    }

    /// Remove every task. Used by the UI tests to start from a clean slate.
    func deleteAllTasks() throws {
        try db.dbQueue.write { db in
            _ = try VaultTask.deleteAll(db)
        }
    }

    func deleteTask(id: Int64) throws {
        try db.dbQueue.write { db in
            _ = try VaultTask.deleteOne(db, key: id)
        }
    }

    func updateTitle(id: Int64, title: String) throws {
        try db.dbQueue.write { db in
            guard var task = try VaultTask.fetchOne(db, key: id) else {
                throw VaultRepositoryError.taskNotFound
            }
            task.title = title
            try task.update(db)
        }
    }

    // MARK: - Reading

    func task(id: Int64) throws -> VaultTask? {
        try db.dbQueue.read { db in
            try VaultTask.fetchOne(db, key: id)
        }
    }

    /// The task the timer should pick back up after the app was killed.
    func runningTask() throws -> VaultTask? {
        try db.dbQueue.read { db in
            try VaultTask
                .filter(VaultTask.Columns.stateRaw == VaultTaskState.running.rawValue)
                .order(VaultTask.Columns.startedAt.desc)
                .fetchOne(db)
        }
    }

    /// A task that was paused when the app was last closed.
    func pausedTask() throws -> VaultTask? {
        try db.dbQueue.read { db in
            try VaultTask
                .filter(VaultTask.Columns.stateRaw == VaultTaskState.paused.rawValue)
                .order(VaultTask.Columns.createdAt.desc)
                .fetchOne(db)
        }
    }

    func allTasks() throws -> [VaultTask] {
        try db.dbQueue.read { db in
            try VaultTask.order(VaultTask.Columns.createdAt.desc).fetchAll(db)
        }
    }

    func tasks(in category: VaultCategory) throws -> [VaultTask] {
        try db.dbQueue.read { db in
            try VaultTask
                .filter(VaultTask.Columns.categoryRaw == category.rawValue)
                .order(VaultTask.Columns.createdAt.desc)
                .fetchAll(db)
        }
    }

    /// Total seconds sitting in the vault — the headline number.
    func totalSavedSeconds() throws -> Int {
        try db.dbQueue.read { db in
            try VaultTask
                .filter(VaultTask.Columns.savedSeconds > 0)
                .fetchAll(db)
                .reduce(0) { $0 + $1.savedSeconds }
        }
    }

    /// Seconds banked since the start of the given day.
    func savedSeconds(since startOfDay: Date) throws -> Int {
        try db.dbQueue.read { db in
            let tasks = try VaultTask
                .filter(VaultTask.Columns.savedSeconds > 0)
                .filter(VaultTask.Columns.finishedAt >= startOfDay)
                .fetchAll(db)
            return tasks.reduce(0) { $0 + $1.savedSeconds }
        }
    }

    /// Banked seconds per day, oldest first — the line chart's input.
    func dailySavedSeries(days: Int, endingAt end: Date = Date(), calendar: Calendar = .current) throws -> [(day: Date, seconds: Int)] {
        let tasks = try db.dbQueue.read { db in
            try VaultTask
                .filter(VaultTask.Columns.savedSeconds > 0)
                .order(VaultTask.Columns.finishedAt.asc)
                .fetchAll(db)
        }

        let comps = calendar.dateComponents([.year, .month, .day], from: end)
        let today = calendar.date(from: comps) ?? end
        let offsets = (0..<max(1, days)).reversed()
        return offsets.map { offset -> (Date, Int) in
            let day = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            let dayComp = calendar.dateComponents([.year, .month, .day], from: day)
            let sum = tasks.reduce(0) { partial, task in
                guard let finished = task.finishedAt else { return partial }
                let f = calendar.dateComponents([.year, .month, .day], from: finished)
                guard f.year == dayComp.year, f.month == dayComp.month, f.day == dayComp.day else {
                    return partial
                }
                return partial + task.savedSeconds
            }
            return (day, sum)
        }
    }

    /// Banked seconds grouped by category — the bar chart's input.
    func savedSecondsByCategory() throws -> [VaultCategory: Int] {
        let tasks = try db.dbQueue.read { db in
            try VaultTask.filter(VaultTask.Columns.savedSeconds > 0).fetchAll(db)
        }
        var result: [VaultCategory: Int] = [:]
        for task in tasks {
            result[task.category, default: 0] += task.savedSeconds
        }
        return result
    }

    /// Everything the calibration helper needs.
    ///
    /// Both early finishes and overruns count. Looking only at the tasks the
    /// user beat would make the median always below 1.0, and the app would
    /// keep telling people to shorten their estimates — the exact opposite of
    /// what "my estimates run long" is supposed to mean.
    func calibrationSample(category: VaultCategory? = nil) throws -> [VaultTask] {
        try db.dbQueue.read { db in
            var request = VaultTask
                .filter(VaultTask.Columns.stateRaw == VaultTaskState.finished.rawValue)
                // The onboarding one-minute demo is not a real measurement of
                // the user's pace — it would skew every category it lands in.
                .filter(VaultTask.Columns.isSample == false)
            if let category {
                request = request.filter(VaultTask.Columns.categoryRaw == category.rawValue)
            }
            return try request.fetchAll(db)
        }
    }
}

enum VaultRepositoryError: Error, LocalizedError {
    case taskNotFound
    case notRunning
    case alreadyRunning

    var errorDescription: String? {
        switch self {
        case .taskNotFound: return "找不到这个任务"
        case .notRunning: return "这个任务没有在计时"
        case .alreadyRunning: return "这个任务已经在计时了"
        }
    }
}
