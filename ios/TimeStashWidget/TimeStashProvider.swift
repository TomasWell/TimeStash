import Foundation
import WidgetKit

/// What the widget shows: the two numbers that matter.
struct VaultEntry: TimelineEntry {
    let date: Date
    let totalSavedSeconds: Int
    let todaySavedSeconds: Int
}

struct TimeStashProvider: TimelineProvider {

    func placeholder(in context: Context) -> VaultEntry {
        VaultEntry(date: Date(), totalSavedSeconds: 3600, todaySavedSeconds: 1200)
    }

    func getSnapshot(in context: Context, completion: @escaping (VaultEntry) -> Void) {
        completion(load())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<VaultEntry>) -> Void) {
        let entry = load()
        // The vault only changes when the user finishes a task, so there is no
        // point waking the widget every few minutes.
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date())
            ?? Date().addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func load() -> VaultEntry {
        let repository = VaultRepository()
        let total = (try? repository.totalSavedSeconds()) ?? 0
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let today = (try? repository.savedSeconds(since: startOfDay)) ?? 0
        return VaultEntry(date: Date(), totalSavedSeconds: total, todaySavedSeconds: today)
    }
}
