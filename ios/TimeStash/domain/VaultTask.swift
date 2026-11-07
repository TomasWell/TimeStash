import Foundation
import GRDB

/// A single "box item": one thing the user planned to do, with an estimate and
/// what it actually took.
///
/// The whole app is one line of logic:  estimate a task, time it, and if you
/// finished early the difference goes into the vault.
struct VaultTask: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable, Equatable {
    static let databaseTableName = "vaultTask"

    /// GRDB needs the column names spelled out. Without this the compiler
    /// synthesises `Columns` as `Never` and every query against the table
    /// fails with "type 'VaultTask.Columns' has no member '...'".
    enum Columns: String, ColumnExpression {
        case id
        case title
        case categoryRaw
        case estimatedSeconds
        case actualSeconds
        case accumulatedSeconds
        case startedAt
        case finishedAt
        case stateRaw
        case savedSeconds
        case createdAt
        case isSample
    }

    var id: Int64?
    var title: String
    var categoryRaw: String
    /// Locked when the timer starts — see `VaultMath.lockedEstimate`.
    var estimatedSeconds: Int
    /// nil while the timer is still running.
    var actualSeconds: Int?
    /// Elapsed time already banked by earlier running stretches. Needed so a
    /// pause (or the app being killed and reopened) does not lose the time
    /// already spent.
    var accumulatedSeconds: Int
    /// Set while running; cleared while paused.
    var startedAt: Date?
    var finishedAt: Date?
    var stateRaw: String
    /// Seconds actually credited to the vault (already capped, see `VaultMath.savedSeconds`).
    var savedSeconds: Int
    var createdAt: Date
    /// True for the onboarding one-minute experiment.
    ///
    /// A 60-second demo task is not evidence about how long the user takes
    /// to write a report, so it must not feed the per-category calibration —
    /// but it *does* belong in the box and in the ledger, because the whole
    /// point of that screen is to see the box move.
    var isSample: Bool

    init(
        id: Int64? = nil,
        title: String,
        category: VaultCategory,
        estimatedSeconds: Int,
        actualSeconds: Int? = nil,
        accumulatedSeconds: Int = 0,
        startedAt: Date? = nil,
        finishedAt: Date? = nil,
        state: VaultTaskState = .planned,
        savedSeconds: Int = 0,
        createdAt: Date = Date(),
        isSample: Bool = false
    ) {
        self.id = id
        self.title = title
        self.categoryRaw = category.rawValue
        self.estimatedSeconds = estimatedSeconds
        self.actualSeconds = actualSeconds
        self.accumulatedSeconds = accumulatedSeconds
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.stateRaw = state.rawValue
        self.savedSeconds = savedSeconds
        self.createdAt = createdAt
        self.isSample = isSample
    }

    /// GRDB writes the generated row id back into the record — without this
    /// every `task.id` would stay nil after an insert.
    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

/// The four buckets a task can live in. Deliberately only four — more than
/// that and nobody remembers which one they picked.
enum VaultCategory: String, CaseIterable, Codable, Sendable, Identifiable {
    case work
    case study
    case life
    case other

    var id: String { rawValue }
}

enum VaultTaskState: String, Codable, Sendable {
    /// Created, timer not started.
    case planned
    /// Timer is running.
    case running
    /// Timer was started and then paused.
    case paused
    /// Completed — may or may not have saved time.
    case finished
    /// User gave up on it. Still recorded, just never credited.
    case abandoned
}

extension VaultTask {
    var category: VaultCategory {
        VaultCategory(rawValue: categoryRaw) ?? .other
    }

    var state: VaultTaskState {
        VaultTaskState(rawValue: stateRaw) ?? .planned
    }

    /// How much this task was over (positive) or under (negative) its estimate.
    var deviationSeconds: Int? {
        guard let actualSeconds else { return nil }
        return actualSeconds - estimatedSeconds
    }

    /// True when the task came in under its estimate.
    var isAhead: Bool {
        guard let deviationSeconds else { return false }
        return deviationSeconds < 0
    }

    /// How long the task has taken so far, counting earlier stretches that
    /// were already banked (pause, or the app being killed and reopened).
    func elapsedSeconds(at now: Date = Date()) -> Int {
        guard state == .running, let startedAt else { return accumulatedSeconds }
        return accumulatedSeconds + max(0, Int(now.timeIntervalSince(startedAt)))
    }
}
