import Foundation

/// Demo data for the store screenshots and the App Store demo recording.
///
/// Seeded through the same repository the app uses, so the seeded tasks are
/// indistinguishable from real ones — the charts, the ledger and the box all
/// read the same tables.
///
/// Guarded by a launch argument so it can never happen in a real user's app.
enum DemoSeed {

    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-seedDemoHistory")
    }

    /// Lets the UI tests and the demo recording jump straight into the app
    /// instead of walking the onboarding every time.
    static var isSkippingOnboarding: Bool {
        ProcessInfo.processInfo.arguments.contains("-skipOnboarding")
    }

    /// Fills the vault with two weeks of believable history.
    ///
    /// - Parameter repository: the store's repository.
    /// - Returns: `true` when data was actually written.
    @discardableResult
    static func seedIfRequested(repository: VaultRepository) -> Bool {
        guard isRequested else { return false }
        guard (try? repository.allTasks().isEmpty) == true else { return false }
        repository.seedDemoHistory()
        return true
    }
}

extension VaultRepository {

    /// Two weeks of finished tasks, spread across categories and days.
    ///
    /// The mix matters: mostly ahead of time (that is the product's story),
    /// a few overruns (so the ledger shows the honest "over" badge too), and
    /// one long task that pushes the total past the first two milestones.
    func seedDemoHistory() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // (day offset, title, category, estimate minutes, actual minutes)
        let plan: [(Int, String, VaultCategory, Int, Int)] = [
            (13, "写周报", .work, 30, 18),
            (13, "晨跑", .life, 30, 26),
            (12, "读一章书", .study, 45, 40),
            (11, "整理文件", .work, 60, 35),
            (10, "回邮件", .work, 15, 9),
            (9, "做饭", .life, 40, 52),
            (8, "背单词", .study, 20, 12),
            (8, "写方案", .work, 90, 55),
            (7, "打扫房间", .life, 60, 41),
            (6, "改代码", .work, 120, 84),
            (5, "看电影", .life, 120, 118),
            (4, "列清单", .work, 20, 11),
            (4, "复习", .study, 45, 27),
            (3, "打电话", .other, 10, 7),
            (2, "写文档", .work, 60, 32),
            (2, "跑步", .life, 30, 21),
            (1, "学新工具", .study, 60, 38),
            (1, "准备会议", .work, 30, 16),
            (0, "写需求", .work, 45, 24),
            (0, "做拉伸", .life, 15, 10)
        ]

        for (dayOffset, title, category, estimateMinutes, actualMinutes) in plan {
            let day = calendar.date(byAdding: .day, value: -dayOffset, to: today) ?? today
            let started = day.addingTimeInterval(TimeInterval(9 * 3600))
            let finished = started.addingTimeInterval(TimeInterval(actualMinutes * 60))

            var task = VaultTask(
                title: title,
                category: category,
                estimatedSeconds: estimateMinutes * 60,
                actualSeconds: actualMinutes * 60,
                accumulatedSeconds: actualMinutes * 60,
                startedAt: started,
                finishedAt: finished,
                state: .finished,
                createdAt: day
            )
            task.savedSeconds = VaultMath.savedSeconds(
                estimatedSeconds: estimateMinutes * 60,
                actualSeconds: actualMinutes * 60
            )
            try? db.dbQueue.write { db in
                try task.insert(db)
            }
        }
    }
}
