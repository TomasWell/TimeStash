import SwiftUI

/// The vault — the app's front door.
///
/// One box, one number, one button. Everything else is secondary.
struct VaultHomeView: View {
    @EnvironmentObject private var store: VaultStore
    @State private var showingNewTask = false
    @State private var showingTimer = false
    /// The task the timer sheet is showing.
    ///
    /// ⚠️ 必须是**记下来的 id**，不能直接读 `store.runningTask`：
    /// 暂停之后 runningTask 变成 nil，sheet 里的 `if let` 会失效 →
    /// **整个计时界面被清空**（2026-11-07 实测：点「暂停」后界面直接空了）。
    @State private var timerTaskID: Int64?

    private var nextMilestone: VaultMilestone? {
        store.milestones.next
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    if let active = store.activeTask {
                        runningBanner(active)
                    }

                    boxSection

                    if let advice = store.calibrationAdvice() {
                        adviceCard(advice)
                    }

                    recentSection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("tab_vault")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingNewTask = true
                    } label: {
                        Label("start_something", systemImage: "plus")
                    }
                    .accessibilityIdentifier("startSomethingButton")
                }
            }
            .sheet(isPresented: $showingNewTask) {
                NewTaskView { taskID in
                    showingNewTask = false
                    store.start(taskID: taskID)
                    timerTaskID = taskID
                    showingTimer = true
                }
            }
            .sheet(isPresented: $showingTimer) {
                TimerView(taskID: timerTaskID ?? 0)
            }
            .refreshable { store.refresh() }
            // A task that was still running when the app was closed: the
            // timer kept counting, so the user decides whether to keep going
            // or close it out. Silently continuing would bank time for
            // something they stopped doing hours ago.
            .alert(
                L("resume_title"),
                isPresented: Binding(
                    get: { store.recoverableTask != nil },
                    set: { if !$0 { store.keepRecoverableTaskRunning() } }
                ),
                presenting: store.recoverableTask
            ) { task in
                Button(L("resume_continue")) { store.keepRecoverableTaskRunning() }
                Button(L("resume_finish"), role: .destructive) { store.finishRecoverableTask() }
            } message: { task in
                Text(L("resume_body", task.title))
            }
        }
    }

    // MARK: - The box

    private var boxSection: some View {
        VStack(spacing: 12) {
            // The box fills inside the current milestone band, so it never
            // empties as the user earns more.
            VaultBoxView(
                totalSeconds: store.boxFill.filled,
                targetSeconds: store.boxFill.target
            )
            .frame(maxWidth: 260)

            VaultTotalView(
                totalSeconds: store.totalSavedSeconds,
                caption: nextMilestone.map { L("vault_next_milestone", VaultFormat.duration($0.thresholdSeconds - store.totalSavedSeconds)) }
            )

            HStack(spacing: 18) {
                statChip(title: "vault_today", value: VaultFormat.compactDuration(store.todaySavedSeconds))
                statChip(title: "vault_total", value: VaultFormat.compactDuration(store.totalSavedSeconds))
            }
            .padding(.top, 2)
        }
        .padding(.top, 12)
    }

    private func statChip(title: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline.monospacedDigit())
            // NOTE: `title` is a String variable, so `Text(title)` uses the
            // verbatim initializer and NEVER looks up the localization table --
            // the screen prints the raw key "vault_today".
            // Must look the key up explicitly. (Found by store screenshot, 2026-11-08.)
            Text(L(title))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground)))
    }

    // MARK: - Running task

    private func runningBanner(_ task: VaultTask) -> some View {
        Button {
            openTimer(for: task)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: task.state == .paused ? "pause.circle" : "timer")
                    .font(.title3)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(VaultFormat.clock(store.elapsedSeconds))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemGroupedBackground)))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("runningTaskBanner")
        .onTapGesture { openTimer(for: task) }
    }

    private func openTimer(for task: VaultTask) {
        timerTaskID = task.id
        showingTimer = true
    }

    // MARK: - Advice

    private func adviceCard(_ key: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lightbulb")
                .foregroundStyle(.yellow)
            Text(L(key))
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.yellow.opacity(0.10)))
    }

    // MARK: - Recent

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("vault_recent"))
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            let deposits = store.tasks.filter { $0.savedSeconds > 0 }.prefix(5)

            if deposits.isEmpty {
                Text(L("vault_empty_hint"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
            } else {
                ForEach(deposits) { task in
                    HStack {
                        Image(systemName: task.isAhead ? "arrow.down.circle.fill" : "circle")
                            .foregroundStyle(task.isAhead ? Color.green : Color.secondary)
                        Text(task.title)
                            .font(.subheadline)
                            .lineLimit(1)
                        Spacer()
                        Text("+\(VaultFormat.compactDuration(task.savedSeconds))")
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(task.isAhead ? Color.green : Color.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
}
