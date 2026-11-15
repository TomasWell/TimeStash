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
    ///
    /// ⚠️ 2026-11-16 P0：任务名**必须走本地化键**（`demo_task_*`），不能写死中文。
    /// 写死中文的后果：换语言拍商店页时，账本/统计页里全是中文条目
    /// → **英文界面夹中文** = Guideline 2.3.3（截图须展示 App 实际使用状态）
    /// + 2.3.7（本地化不完整）双重风险。CommutePilot 早就用同一套路
    /// （`L("event_wake")`），一份数据出 43 个语言。
    func seedDemoHistory() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // (day offset, 本地化 key, category, estimate minutes, actual minutes)
        let plan: [(Int, String, VaultCategory, Int, Int)] = [
            (13, "demo_task_report", .work, 30, 18),
            (13, "demo_task_run", .life, 30, 26),
            (12, "demo_task_read", .study, 45, 40),
            (11, "demo_task_tidy", .work, 60, 35),
            (10, "demo_task_email", .work, 15, 9),
            (9, "demo_task_cook", .life, 40, 52),
            (8, "demo_task_words", .study, 20, 12),
            (8, "demo_task_plan", .work, 90, 55),
            (7, "demo_task_clean", .life, 60, 41),
            (6, "demo_task_code", .work, 120, 84),
            (5, "demo_task_movie", .life, 120, 118),
            (4, "demo_task_list", .work, 20, 11),
            (4, "demo_task_review", .study, 45, 27),
            (3, "demo_task_call", .other, 10, 7),
            (2, "demo_task_doc", .work, 60, 32),
            (2, "demo_task_jog", .life, 30, 21),
            (1, "demo_task_learn", .study, 60, 38),
            (1, "demo_task_meeting", .work, 30, 16),
            (0, "demo_task_spec", .work, 45, 24),
            (0, "demo_task_stretch", .life, 15, 10)
        ]

        for (dayOffset, titleKey, category, estimateMinutes, actualMinutes) in plan {
            // 查不到就退回英文基准（宁可英文，也不要把 key 本身显示给用户）
            let title = L(titleKey)
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
