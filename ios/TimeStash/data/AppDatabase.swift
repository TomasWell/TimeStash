import Foundation
import GRDB

/// The app's local database.
///
/// Plain SQLite on disk — no account, no server, no sync. The widget
/// extension reads the same file through the shared App Group container, so
/// a task finished in the app shows up on the Home Screen without any
/// network round trip.
final class AppDatabase: @unchecked Sendable {

    static let appGroupIdentifier = "group.com.junxf.timestash"
    static let fileName = "timestash.sqlite"

    static let shared = AppDatabase()

    let dbQueue: DatabaseQueue

    private init() {
        dbQueue = try! DatabaseQueue(path: AppDatabase.databasePath())
        try! AppDatabase.migrator.migrate(dbQueue)
    }

    /// Used by tests: an in-memory database, no App Group, no disk.
    init(inMemory: Bool) throws {
        if inMemory {
            dbQueue = try DatabaseQueue()
        } else {
            dbQueue = try DatabaseQueue(path: AppDatabase.databasePath())
        }
        try AppDatabase.migrator.migrate(dbQueue)
    }

    // MARK: - Location

    /// The App Group container when it is available (real device, signed
    /// build), otherwise the app's own container (simulator without the
    /// entitlement). The widget uses the same fallback so both sides always
    /// look at the same file.
    static func databaseURL() -> URL {
        if let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) {
            return groupURL.appendingPathComponent(fileName)
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent(fileName)
    }

    private static func databasePath() -> String {
        databaseURL().path
    }

    // MARK: - Schema

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        // ⚠️ 迁移历史只能往后加，**不能回头改已发布的迁移**，也不能复用
        //    已经跑过的迁移编号 —— GRDB 用 `grdb_migrations` 表记「跑过哪些编号」，
        //    编号跑过就永远不会再跑，改了编号等于没改。
        //
        // 2026-11-07 实测（开发机上「建不出任务」的根因）：
        //   v1 曾经被事后加过 `accumulatedSeconds`，而那台机器上早已存在一个
        //   按旧 v1 建好的库 → GRDB 认为 v1 已应用、不会重跑 → 那张表永远缺
        //   这一列 → 每次 insert 都报 "no such column: accumulatedSeconds"
        //   → createTask 直接抛错 → 引导页的 1 分钟体验任务建不出来
        //   → UI 测试点「开始这一分钟」后「完成」按钮永远不出现。
        //
        // 修法：v1 回到最初的形状，新列一律走**新编号**的迁移，
        // 并且加之前先查列在不在（新装的库可能已经有了）。
        migrator.registerMigration("v1") { db in
            try db.create(table: VaultTask.databaseTableName) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("title", .text).notNull()
                t.column("categoryRaw", .text).notNull().defaults(to: VaultCategory.other.rawValue)
                t.column("estimatedSeconds", .integer).notNull()
                t.column("actualSeconds", .integer)
                t.column("startedAt", .datetime)
                t.column("finishedAt", .datetime)
                t.column("stateRaw", .text).notNull().defaults(to: VaultTaskState.planned.rawValue)
                t.column("savedSeconds", .integer).notNull().defaults(to: 0)
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(index: "vaultTask_createdAt", on: VaultTask.databaseTableName, columns: ["createdAt"])
            try db.create(index: "vaultTask_state", on: VaultTask.databaseTableName, columns: ["stateRaw"])
        }

        // 引导的 1 分钟体验任务：进箱子、进账本，但不进分类校准
        // （60 秒的演示不能代表用户写一份报告要多久）。
        migrator.registerMigration("v2") { db in
            let table = VaultTask.databaseTableName
            let existing = try db.columns(in: table).map(\.name)
            if !existing.contains("isSample") {
                try db.alter(table: table) { t in
                    t.add(column: "isSample", .boolean).notNull().defaults(to: false)
                }
            }
        }

        // 已用掉的时长（暂停 / 杀进程恢复靠它）——见上面的说明，
        // 必须用新编号 v3，v1/v2 在老库上已经跑过了。
        migrator.registerMigration("v3") { db in
            let table = VaultTask.databaseTableName
            let existing = try db.columns(in: table).map(\.name)
            if !existing.contains("accumulatedSeconds") {
                try db.alter(table: table) { t in
                    t.add(column: "accumulatedSeconds", .integer).notNull().defaults(to: 0)
                }
            }
        }

        return migrator
    }
}
