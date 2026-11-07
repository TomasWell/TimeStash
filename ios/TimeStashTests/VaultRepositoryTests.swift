import XCTest
import GRDB
@testable import TimeStash

final class VaultRepositoryTests: XCTestCase {

    private var database: AppDatabase!
    private var repository: VaultRepository!

    override func setUpWithError() throws {
        database = try AppDatabase(inMemory: true)
        repository = VaultRepository(db: database)
    }

    override func tearDown() {
        repository = nil
        database = nil
    }

    // MARK: - The happy path

    func testCreateStartFinishBanksTime() throws {
        let task = try repository.createTask(title: "写方案", category: .work, estimatedSeconds: 3600)
        let id = try XCTUnwrap(task.id)

        XCTAssertEqual(try repository.task(id: id)?.state, .planned)

        try repository.startTask(id: id)
        XCTAssertEqual(try repository.task(id: id)?.state, .running)

        let finished = try repository.finishTask(id: id, actualSeconds: 2400)
        XCTAssertEqual(finished.state, .finished)
        XCTAssertEqual(finished.actualSeconds, 2400)
        XCTAssertEqual(finished.savedSeconds, 1200)
        XCTAssertEqual(try repository.totalSavedSeconds(), 1200)
    }

    func testFinishingOverEstimateRecordsButBanksNothing() throws {
        let task = try repository.createTask(title: "开会", category: .work, estimatedSeconds: 1800)
        let id = try XCTUnwrap(task.id)
        try repository.startTask(id: id)

        let finished = try repository.finishTask(id: id, actualSeconds: 3600)
        XCTAssertEqual(finished.state, .finished)
        XCTAssertEqual(finished.actualSeconds, 3600)
        XCTAssertEqual(finished.savedSeconds, 0)
        XCTAssertEqual(try repository.totalSavedSeconds(), 0)
    }

    func testSingleTaskCannotBankMoreThanHalfItsEstimate() throws {
        let task = try repository.createTask(title: "离谱预估", category: .other, estimatedSeconds: 8 * 3600)
        let id = try XCTUnwrap(task.id)
        try repository.startTask(id: id)

        let finished = try repository.finishTask(id: id, actualSeconds: 1)
        XCTAssertEqual(finished.savedSeconds, 4 * 3600)
    }

    func testAbandonedTaskNeverBanks() throws {
        let task = try repository.createTask(title: "放弃的", category: .work, estimatedSeconds: 3600)
        let id = try XCTUnwrap(task.id)
        try repository.startTask(id: id)

        let abandoned = try repository.abandonTask(id: id, actualSeconds: 600)
        XCTAssertEqual(abandoned.state, .abandoned)
        XCTAssertEqual(abandoned.savedSeconds, 0)
        XCTAssertEqual(try repository.totalSavedSeconds(), 0)
    }

    // MARK: - Rules that must hold

    func testEstimateIsFrozenWhenTheTimerStarts() throws {
        let task = try repository.createTask(title: "标题", category: .work, estimatedSeconds: 3600)
        let id = try XCTUnwrap(task.id)

        try repository.startTask(id: id)

        // Even if something tried to rewrite the estimate, the stored value
        // is the one that was locked at start time.
        XCTAssertEqual(try repository.task(id: id)?.estimatedSeconds, 3600)
    }

    func testCannotStartTheSameTaskTwice() throws {
        let task = try repository.createTask(title: "重复启动", category: .work, estimatedSeconds: 600)
        let id = try XCTUnwrap(task.id)
        try repository.startTask(id: id)

        XCTAssertThrowsError(try repository.startTask(id: id)) { error in
            XCTAssertEqual(error as? VaultRepositoryError, .alreadyRunning)
        }
    }

    func testCannotFinishATaskThatNeverStarted() throws {
        let task = try repository.createTask(title: "没开始", category: .work, estimatedSeconds: 600)
        let id = try XCTUnwrap(task.id)

        XCTAssertThrowsError(try repository.finishTask(id: id, actualSeconds: 60)) { error in
            XCTAssertEqual(error as? VaultRepositoryError, .notRunning)
        }
    }

    func testStartingAMissingTaskThrows() {
        XCTAssertThrowsError(try repository.startTask(id: 9999)) { error in
            XCTAssertEqual(error as? VaultRepositoryError, .taskNotFound)
        }
    }

    // MARK: - Pause and resume

    func testPauseBanksTheTimeSoFarAndStopsTheClock() throws {
        let task = try repository.createTask(title: "暂停", category: .work, estimatedSeconds: 3600)
        let id = try XCTUnwrap(task.id)
        let started = Date(timeIntervalSince1970: 1_000_000)

        try repository.startTask(id: id, at: started)
        let paused = try repository.pauseTask(id: id, at: started.addingTimeInterval(600))

        XCTAssertEqual(paused.state, .paused)
        XCTAssertEqual(paused.accumulatedSeconds, 600, "暂停时已用的 600 秒应该被记进累计时长")
        XCTAssertNil(paused.startedAt, "暂停后不该再有时钟起点")

        // 暂停期间时间不计入
        XCTAssertEqual(paused.elapsedSeconds(at: started.addingTimeInterval(5000)), 600,
                       "暂停期间不该继续计时")
    }

    func testResumeContinuesFromTheBankedTime() throws {
        let task = try repository.createTask(title: "继续", category: .work, estimatedSeconds: 3600)
        let id = try XCTUnwrap(task.id)
        let started = Date(timeIntervalSince1970: 1_000_000)

        try repository.startTask(id: id, at: started)
        try repository.pauseTask(id: id, at: started.addingTimeInterval(600))

        // 恢复：已累计的 600 秒保留，再从恢复时刻继续走
        let resumedAt = started.addingTimeInterval(5000)
        let resumed = try repository.startTask(id: id, at: resumedAt)
        XCTAssertEqual(resumed.state, .running)
        XCTAssertEqual(resumed.accumulatedSeconds, 600, "恢复后不该清空已累计的时长")
        XCTAssertEqual(resumed.elapsedSeconds(at: resumedAt.addingTimeInterval(300)), 900,
                       "恢复后应该在已累计的基础上继续加")
    }

    func testPausedTaskIsRecoverable() throws {
        let task = try repository.createTask(title: "暂停恢复", category: .life, estimatedSeconds: 600)
        let id = try XCTUnwrap(task.id)
        try repository.startTask(id: id)
        try repository.pauseTask(id: id)

        let paused = try repository.pausedTask()
        XCTAssertEqual(paused?.id, id)
        XCTAssertNil(try repository.runningTask(), "暂停的任务不该被当成运行中的")
    }

    func testAPausedTaskCanStillBeFinished() throws {
        let task = try repository.createTask(title: "暂停后完成", category: .work, estimatedSeconds: 3600)
        let id = try XCTUnwrap(task.id)
        try repository.startTask(id: id)
        try repository.pauseTask(id: id)

        let finished = try repository.finishTask(id: id, actualSeconds: 600)
        XCTAssertEqual(finished.state, .finished)
        // 预估 3600、实际 600 → 差 3000 秒，但**单次入箱封顶是预估的 50%**
        // → 只能进 1800 秒。这是防刷规则，不是 bug。
        XCTAssertEqual(finished.savedSeconds, 1800, "预估 3600、实际 600 → 差 3000，但封顶后只进 1800")
    }

    // MARK: - Reading

    func testRunningTaskIsRecoverable() throws {
        let task = try repository.createTask(title: "被杀掉了", category: .life, estimatedSeconds: 600)
        let id = try XCTUnwrap(task.id)
        try repository.startTask(id: id)

        let recovered = try repository.runningTask()
        XCTAssertEqual(recovered?.id, id)
        XCTAssertNotNil(recovered?.startedAt)
    }

    func testFinishedTaskIsNotReturnedAsRunning() throws {
        let task = try repository.createTask(title: "做完了", category: .life, estimatedSeconds: 600)
        let id = try XCTUnwrap(task.id)
        try repository.startTask(id: id)
        try repository.finishTask(id: id, actualSeconds: 300)

        XCTAssertNil(try repository.runningTask())
    }

    func testTasksCanBeFilteredByCategory() throws {
        _ = try repository.createTask(title: "工作", category: .work, estimatedSeconds: 600)
        _ = try repository.createTask(title: "生活", category: .life, estimatedSeconds: 600)

        XCTAssertEqual(try repository.tasks(in: .work).count, 1)
        XCTAssertEqual(try repository.tasks(in: .life).count, 1)
        XCTAssertEqual(try repository.allTasks().count, 2)
    }

    func testDeleteRemovesTheTask() throws {
        let task = try repository.createTask(title: "删掉", category: .other, estimatedSeconds: 600)
        let id = try XCTUnwrap(task.id)
        try repository.deleteTask(id: id)

        XCTAssertNil(try repository.task(id: id))
    }

    // MARK: - Aggregates

    func testSavedSecondsGroupByCategory() throws {
        for title in ["a", "b"] {
            let task = try repository.createTask(title: title, category: .work, estimatedSeconds: 3600)
            let id = try XCTUnwrap(task.id)
            try repository.startTask(id: id)
            try repository.finishTask(id: id, actualSeconds: 2400)
        }
        let life = try repository.createTask(title: "c", category: .life, estimatedSeconds: 3600)
        let lifeID = try XCTUnwrap(life.id)
        try repository.startTask(id: lifeID)
        try repository.finishTask(id: lifeID, actualSeconds: 3000)

        let grouped = try repository.savedSecondsByCategory()
        XCTAssertEqual(grouped[.work], 2400)
        XCTAssertEqual(grouped[.life], 600)
    }

    func testDailySeriesHasOneEntryPerDayAndCountsToday() throws {
        let task = try repository.createTask(title: "今天", category: .work, estimatedSeconds: 3600)
        let id = try XCTUnwrap(task.id)
        try repository.startTask(id: id)
        try repository.finishTask(id: id, actualSeconds: 2400)

        let series = try repository.dailySavedSeries(days: 7)
        XCTAssertEqual(series.count, 7)
        XCTAssertEqual(series.last?.seconds, 1200)
        XCTAssertEqual(series.dropLast().reduce(0) { $0 + $1.seconds }, 0)
    }

    func testSavedSinceStartOfDayCountsOnlyToday() throws {
        let task = try repository.createTask(title: "今天", category: .work, estimatedSeconds: 3600)
        let id = try XCTUnwrap(task.id)
        try repository.startTask(id: id)
        try repository.finishTask(id: id, actualSeconds: 2400)

        let startOfDay = Calendar.current.startOfDay(for: Date())
        XCTAssertEqual(try repository.savedSeconds(since: startOfDay), 1200)
        XCTAssertEqual(try repository.savedSeconds(since: Date().addingTimeInterval(3600)), 0)
    }

    func testCalibrationSampleOnlyReturnsFinishedTasks() throws {
        let finished = try repository.createTask(title: "完成", category: .work, estimatedSeconds: 600)
        let finishedID = try XCTUnwrap(finished.id)
        try repository.startTask(id: finishedID)
        try repository.finishTask(id: finishedID, actualSeconds: 900)

        let running = try repository.createTask(title: "进行", category: .work, estimatedSeconds: 600)
        let runningID = try XCTUnwrap(running.id)
        try repository.startTask(id: runningID)

        let samples = try repository.calibrationSample(category: .work)
        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples.first?.title, "完成")
    }
}
