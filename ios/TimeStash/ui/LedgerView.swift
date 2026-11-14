import SwiftUI

/// The ledger — every task, estimated vs actual.
///
/// This is the part the user checks when they want facts rather than
/// encouragement.
struct LedgerView: View {
    @EnvironmentObject private var store: VaultStore
    @State private var filter: VaultCategory?

    private var filtered: [VaultTask] {
        guard let filter else { return store.tasks }
        return store.tasks.filter { $0.category == filter }
    }

    var body: some View {
        NavigationStack {
            List {
                if filtered.isEmpty {
                    // ContentUnavailableView is iOS 17+; this app supports 16,
                    // so the empty state is drawn by hand.
                    VStack(spacing: 10) {
                        Image(systemName: "tray")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text(L("ledger_empty_title"))
                            .font(.headline)
                        Text(L("ledger_empty_hint"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 36)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(filtered) { task in
                        row(task)
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            if let id = filtered[index].id {
                                store.delete(taskID: id)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("tab_ledger")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("ledger_filter_all") { filter = nil }
                        ForEach(VaultCategory.allCases) { c in
                            Button("category_\(c.rawValue)") { filter = c }
                        }
                    } label: {
                        Label("ledger_filter", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
            }
        }
    }

    private func row(_ task: VaultTask) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol(for: task))
                .foregroundStyle(task.isAhead ? Color.green : Color.secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.body)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(L("category_\(task.category.rawValue)"))
                    if let deviation = task.deviationSeconds {
                        Text("·")
                        Text(VaultFormat.compactDuration(abs(deviation)))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 3) {
                if let actual = task.actualSeconds {
                    Text(VaultFormat.compactDuration(actual))
                        .font(.subheadline.monospacedDigit())
                    if let deviation = task.deviationSeconds {
                        DeviationBadge(deviationSeconds: deviation)
                    }
                } else {
                    Text(VaultFormat.compactDuration(task.estimatedSeconds))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text(L(task.state == .running ? "timer_title" : "new_task_estimate"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func symbol(for task: VaultTask) -> String {
        switch task.state {
        case .finished: return task.isAhead ? "checkmark.circle.fill" : "exclamationmark.circle"
        case .running: return "timer"
        case .paused: return "pause.circle"
        case .abandoned: return "xmark.circle"
        case .planned: return "circle"
        }
    }
}
