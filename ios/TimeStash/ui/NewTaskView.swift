import SwiftUI

/// Create a task: what, how long, which bucket.
struct NewTaskView: View {
    @EnvironmentObject private var store: VaultStore
    @Environment(\.dismiss) private var dismiss

    /// Called with the new task's id so the caller can start it.
    let onCreate: (Int64) -> Void

    @State private var title = ""
    @State private var category: VaultCategory = .work
    @State private var estimateMinutes = 30

    private let quickMinutes = [15, 30, 45, 60, 90]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("new_task_title_placeholder", text: $title)
                        .accessibilityIdentifier("newTaskTitleField")
                }

                Section {
                    Picker("new_task_category", selection: $category) {
                        ForEach(VaultCategory.allCases) { c in
                            Text(L("category_\(c.rawValue)")).tag(c)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("newTaskCategoryPicker")
                }

                Section {
                    HStack(spacing: 8) {
                        ForEach(quickMinutes, id: \.self) { minutes in
                            Button {
                                estimateMinutes = minutes
                            } label: {
                                Text("\(minutes)")
                                    .font(.subheadline.weight(.medium))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(estimateMinutes == minutes ? Color.accentColor.opacity(0.18) : Color.clear)
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("estimateChip\(minutes)")
                        }
                    }

                    Stepper(value: $estimateMinutes, in: 1...480, step: 5) {
                        HStack {
                            Text("new_task_estimate")
                            Spacer()
                            Text("\(estimateMinutes) min")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                } footer: {
                    Text("new_task_estimate_footer")
                }
            }
            .navigationTitle("new_task_title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("start") { create() }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("createAndStartButton")
                }
            }
            .onAppear {
                estimateMinutes = max(1, store.suggestedEstimate(for: category) / 60)
            }
            .onChange(of: category) { newValue in
                // Keep the estimate honest when the user switches bucket.
                estimateMinutes = max(1, store.suggestedEstimate(for: newValue) / 60)
            }
        }
    }

    private func create() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let task = store.createTask(
            title: trimmed,
            category: category,
            estimatedSeconds: estimateMinutes * 60
        )
        if let id = task?.id {
            onCreate(id)
        }
        dismiss()
    }
}
