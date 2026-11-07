import SwiftUI

/// The running timer.
///
/// Its whole job is to make the end of a task feel good: you can see, live,
/// how many minutes are going to land in the box.
struct TimerView: View {
    @EnvironmentObject private var store: VaultStore
    @Environment(\.dismiss) private var dismiss

    let taskID: Int64

    @State private var showQuitConfirm = false

    private var task: VaultTask? {
        store.tasks.first { $0.id == taskID }
    }

    /// This task's own elapsed time — not a global value, which could
    /// belong to a different task.
    private var elapsed: Int {
        store.elapsedSeconds(for: taskID)
    }

    private var isPaused: Bool {
        task?.state == .paused
    }

    /// What the vault will gain if the user finishes right now.
    ///
    /// Uses the **capped** value — the number the user will actually see
    /// grow, not the raw difference. Showing "完成 3 小时" when only 30
    /// minutes will land in the box is a lie the app cannot afford.
    private var pendingSaving: Int {
        guard let task else { return 0 }
        return VaultMath.savedSeconds(
            estimatedSeconds: task.estimatedSeconds,
            actualSeconds: elapsed
        )
    }

    private var isOverEstimate: Bool {
        guard let task else { return false }
        return elapsed >= task.estimatedSeconds
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 26) {
                Spacer(minLength: 0)

                VStack(spacing: 8) {
                    Text(task?.title ?? "")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    Text(L("category_\(task?.category.rawValue ?? "other")"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(VaultFormat.clock(elapsed))
                    .font(.system(size: 64, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .accessibilityIdentifier("timerClock")

                estimateRow

                if isPaused {
                    Text(L("timer_paused_hint"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("pausedHint")
                }

                Spacer(minLength: 0)

                if isOverEstimate {
                    Text("timer_over_estimate")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                } else {
                    Text(L("timer_pending_saving", VaultFormat.duration(pendingSaving)))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.green)
                        .contentTransition(.numericText())
                        .accessibilityIdentifier("pendingSavingLabel")
                }

                VStack(spacing: 10) {
                    Button {
                        let gained = store.finish(taskID: taskID)
                        dismiss()
                        if gained > 0 { celebrate(gained) }
                    } label: {
                        Text(isOverEstimate ? "timer_finish_anyway" : "timer_finish_early")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Color.accentColor))
                            .foregroundStyle(.white)
                    }
                    .accessibilityIdentifier("finishTaskButton")

                    // Pause / resume. Paused time is banked into the task's
                    // accumulator, so it never counts against the estimate.
                    Button {
                        if isPaused {
                            store.start(taskID: taskID)
                        } else {
                            store.pause(taskID: taskID)
                        }
                    } label: {
                        Text(isPaused ? L("timer_resume") : L("timer_pause"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("pauseResumeButton")

                    Button {
                        showQuitConfirm = true
                    } label: {
                        Text("timer_give_up")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("giveUpButton")
                }
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 24)
            .navigationTitle("timer_title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("close") { dismiss() }
                }
            }
            .confirmationDialog("timer_quit_confirm", isPresented: $showQuitConfirm, titleVisibility: .visible) {
                Button("timer_give_up", role: .destructive) {
                    store.abandon(taskID: taskID)
                    dismiss()
                }
                Button("cancel", role: .cancel) {}
            }
        }
    }

    private var estimateRow: some View {
        HStack {
            VStack(spacing: 2) {
                Text("timer_estimate")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(VaultFormat.duration(task?.estimatedSeconds ?? 0))
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
            }
            Spacer()
            Image(systemName: "arrow.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
            VStack(spacing: 2) {
                Text("timer_used")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(VaultFormat.duration(elapsed))
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground)))
    }

    /// A short haptic + banner so the win is felt, not just read.
    private func celebrate(_ seconds: Int) {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        store.lastDeposit = store.tasks.first { $0.savedSeconds == seconds }
    }
}
