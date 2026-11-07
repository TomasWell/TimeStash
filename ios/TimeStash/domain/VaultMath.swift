import Foundation

/// All the arithmetic behind the vault.
///
/// Two rules matter and both live here so they can be unit-tested in isolation:
///
/// 1. **The estimate locks when the timer starts.** Editing it mid-run would
///    let every task be "finished early" by bumping the number up.
/// 2. **A single task can credit at most 50% of its estimate.** Without this,
///    "estimate 8 hours, finish in 1 second" would bank a fake 8 hours. There
///    is no leaderboard and nothing to share, so cheating here only fools the
///    user — a light guard is enough, and the saved data stays trustworthy.
enum VaultMath {

    /// The largest share of an estimate a single task may credit.
    static let maxSavedRatio: Double = 0.5

    /// Seconds a finished task contributes to the vault.
    ///
    /// - Returns: `0` when the task was not finished ahead of its estimate.
    static func savedSeconds(estimatedSeconds: Int, actualSeconds: Int) -> Int {
        guard estimatedSeconds > 0, actualSeconds >= 0, actualSeconds < estimatedSeconds else {
            return 0
        }
        let difference = estimatedSeconds - actualSeconds
        let cap = Int((Double(estimatedSeconds) * maxSavedRatio).rounded(.down))
        return max(0, min(difference, cap))
    }

    /// The estimate a task should start with once the timer runs — locked.
    static func lockedEstimate(_ estimatedSeconds: Int) -> Int {
        max(0, estimatedSeconds)
    }

    /// How much the user's estimates run long, as a multiplier.
    ///
    /// `1.0` means their estimates are dead on. `1.3` means "if you say one
    /// hour, plan for 78 minutes".
    ///
    /// - Returns: `nil` until there are enough samples to mean anything.
    static func calibrationFactor(
        tasks: [VaultTask],
        category: VaultCategory? = nil
    ) -> Double? {
        let usable = tasks.filter { task in
            task.state == .finished
                && task.estimatedSeconds > 0
                && (task.actualSeconds ?? 0) > 0
                && !task.isSample
                && (category == nil || task.category == category)
        }
        guard usable.count >= minimumCalibrationSamples else { return nil }

        let ratios = usable
            .map { Double($0.actualSeconds ?? 0) / Double($0.estimatedSeconds) }
            .sorted()
        return median(ratios)
    }

    /// Below this many finished tasks the average is noise, not a signal.
    static let minimumCalibrationSamples = 5

    /// A suggestion the user can act on, or `nil` when there is nothing worth
    /// saying yet.
    static func calibrationAdvice(
        tasks: [VaultTask],
        category: VaultCategory? = nil
    ) -> String? {
        guard let factor = calibrationFactor(tasks: tasks, category: category) else { return nil }
        guard abs(factor - 1.0) >= 0.05 else { return nil }
        return factor > 1.0
            ? "your_estimates_run_long"
            : "your_estimates_run_short"
    }

    static func median(_ sortedValues: [Double]) -> Double {
        guard !sortedValues.isEmpty else { return 0 }
        let middle = sortedValues.count / 2
        if sortedValues.count % 2 == 1 {
            return sortedValues[middle]
        }
        return (sortedValues[middle - 1] + sortedValues[middle]) / 2
    }
}

/// A rung on the ladder. The early ones are deliberately tiny so a brand new
/// user can earn one on their first day.
struct VaultMilestone: Identifiable, Sendable, Equatable {
    let id: String
    let thresholdSeconds: Int
    let titleKey: String
    let symbolName: String

    static let all: [VaultMilestone] = [
        VaultMilestone(id: "m30", thresholdSeconds: 30 * 60, titleKey: "milestone_30m", symbolName: "sparkle"),
        VaultMilestone(id: "m1h", thresholdSeconds: 60 * 60, titleKey: "milestone_1h", symbolName: "hourglass"),
        VaultMilestone(id: "m4h", thresholdSeconds: 4 * 60 * 60, titleKey: "milestone_4h", symbolName: "sun.horizon"),
        VaultMilestone(id: "m8h", thresholdSeconds: 8 * 60 * 60, titleKey: "milestone_8h", symbolName: "sun.max"),
        VaultMilestone(id: "m40h", thresholdSeconds: 40 * 60 * 60, titleKey: "milestone_40h", symbolName: "calendar"),
        VaultMilestone(id: "m160h", thresholdSeconds: 160 * 60 * 60, titleKey: "milestone_160h", symbolName: "star.circle")
    ]

    /// The milestones already reached, and the next one still to earn.
    static func progress(totalSeconds: Int) -> (earned: [VaultMilestone], next: VaultMilestone?) {
        let earned = all.filter { totalSeconds >= $0.thresholdSeconds }
        let next = all.first { totalSeconds < $0.thresholdSeconds }
        return (earned, next)
    }

    /// How full the box is, measured **within the current milestone band**.
    ///
    /// ⚠️ Why not `total / nextMilestone`? That makes the box *shrink* as the
    /// user earns more: 8 hours banked with the next badge at 40 hours would
    /// show 20% full — a box that empties as you succeed. Measuring from the
    /// last earned milestone means the box fills 0 → 100% inside every band,
    /// then rolls over into the next one.
    ///
    /// - Returns: seconds banked inside the current band, and the band's size.
    static func band(totalSeconds: Int) -> (filled: Int, target: Int) {
        let total = max(0, totalSeconds)
        let earned = all.filter { total >= $0.thresholdSeconds }
        let base = earned.last?.thresholdSeconds ?? 0
        let next = all.first { total < $0.thresholdSeconds }
        guard let next else {
            // Every milestone earned — the box is simply full.
            return (max(0, total - base), max(1, total - base))
        }
        return (total - base, next.thresholdSeconds - base)
    }
}

/// The pure shape of a duration: how many hours, minutes and seconds.
///
/// Kept separate from the wording on purpose. Which unit to use (seconds /
/// minutes / hours) and how to split the number is **logic** and must be
/// unit-tested; the words themselves are **translations** and live in the
/// .strings files. Mixing them means every test has to hardcode a language
/// ("1 小时"), and the test then fails the moment the app's strings are
/// localized — which is exactly what happened on 2026-11-07.
struct VaultDurationComponents: Equatable {
    let hours: Int
    let minutes: Int
    let seconds: Int

    var totalSeconds: Int { hours * 3600 + minutes * 60 + seconds }
}

enum VaultFormat {

    /// Split a duration into hours / minutes / seconds.
    ///
    /// One rule: **never show a fraction of an hour.** "40 分钟" reads fine;
    /// "0.7 小时" does not. So 45 minutes stays 45 minutes, and 3600 seconds
    /// becomes exactly 1 hour.
    static func components(_ seconds: Int) -> VaultDurationComponents {
        let total = max(0, seconds)
        return VaultDurationComponents(
            hours: total / 3600,
            minutes: (total % 3600) / 60,
            seconds: total % 60
        )
    }

    /// e.g. "2 小时 15 分钟" / "1 分 30 秒" / "45 分钟"
    ///
    /// The wording comes from the .strings tables, so it is correct in every
    /// language. The unit words and the word order differ per language, so
    /// the whole pattern is one key rather than a noun pasted after a number.
    static func duration(_ seconds: Int) -> String {
        let c = components(seconds)
        if c.hours > 0 {
            return c.minutes == 0
                ? L("fmt_hours", c.hours)
                : L("fmt_hours_minutes", c.hours, c.minutes)
        }
        if c.minutes > 0 {
            return c.seconds == 0
                ? L("fmt_minutes", c.minutes)
                : L("fmt_minutes_seconds", c.minutes, c.seconds)
        }
        return L("fmt_seconds", c.seconds)
    }

    /// The compact form used where space is tight (widget, badges).
    static func compactDuration(_ seconds: Int) -> String {
        let c = components(seconds)
        if c.hours > 0 {
            return c.minutes == 0
                ? L("fmt_compact_hours", c.hours)
                : L("fmt_compact_hours_minutes", c.hours, c.minutes)
        }
        if c.minutes > 0 { return L("fmt_compact_minutes", c.minutes) }
        return L("fmt_compact_seconds", c.seconds)
    }

    /// "HH:MM:SS" for the running timer.
    static func clock(_ seconds: Int) -> String {
        let total = max(0, seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, secs)
    }
}
