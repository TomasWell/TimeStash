import XCTest
@testable import TimeStash

final class VaultMathTests: XCTestCase {

    // MARK: - The 50% cap

    func testFinishingAheadOfEstimateBanksTheDifference() {
        // Estimated 60 minutes, took 40 → 20 minutes banked (under the cap).
        XCTAssertEqual(VaultMath.savedSeconds(estimatedSeconds: 3600, actualSeconds: 2400), 1200)
    }

    func testFinishingExactlyOnTimeBanksNothing() {
        XCTAssertEqual(VaultMath.savedSeconds(estimatedSeconds: 3600, actualSeconds: 3600), 0)
    }

    func testOverrunningBanksNothing() {
        XCTAssertEqual(VaultMath.savedSeconds(estimatedSeconds: 3600, actualSeconds: 5400), 0)
    }

    func testSingleTaskCannotBankMoreThanHalfItsEstimate() {
        // Estimated 8 hours, finished in 1 second — the cap stops it.
        let saved = VaultMath.savedSeconds(estimatedSeconds: 8 * 3600, actualSeconds: 1)
        XCTAssertEqual(saved, 4 * 3600)
    }

    func testCapAppliesToTinyEstimatesToo() {
        // 1 minute estimate, finished in 0 seconds → cap is 30 seconds.
        XCTAssertEqual(VaultMath.savedSeconds(estimatedSeconds: 60, actualSeconds: 0), 30)
    }

    func testZeroOrNegativeInputsAreSafe() {
        XCTAssertEqual(VaultMath.savedSeconds(estimatedSeconds: 0, actualSeconds: 0), 0)
        XCTAssertEqual(VaultMath.savedSeconds(estimatedSeconds: 3600, actualSeconds: -10), 0)
    }

    // MARK: - Estimate locking

    func testEstimateIsLockedAndNeverNegative() {
        XCTAssertEqual(VaultMath.lockedEstimate(1800), 1800)
        XCTAssertEqual(VaultMath.lockedEstimate(-5), 0)
    }

    // MARK: - Calibration

    func testCalibrationNeedsEnoughSamples() {
        let tasks = (0..<4).map { index in
            VaultTask(
                title: "t\(index)",
                category: .work,
                estimatedSeconds: 600,
                actualSeconds: 900,
                state: .finished
            )
        }
        XCTAssertNil(VaultMath.calibrationFactor(tasks: tasks))
    }

    func testCalibrationReportsHowMuchEstimatesRunLong() {
        let tasks = (0..<6).map { index in
            VaultTask(
                title: "t\(index)",
                category: .work,
                estimatedSeconds: 600,
                actualSeconds: 900,
                state: .finished
            )
        }
        let factor = VaultMath.calibrationFactor(tasks: tasks)
        XCTAssertNotNil(factor)
        XCTAssertEqual(factor!, 1.5, accuracy: 0.001)
    }

    func testCalibrationIgnoresUnfinishedTasks() {
        // 10 tasks: 5 finished (all overran), 5 still running.
        // Only the finished ones count, so the factor is 900/600 = 1.5.
        let tasks = (0..<10).map { index in
            VaultTask(
                title: "t\(index)",
                category: .work,
                estimatedSeconds: 600,
                actualSeconds: index % 2 == 0 ? 900 : nil,
                state: index % 2 == 0 ? .finished : .running
            )
        }
        let factor = VaultMath.calibrationFactor(tasks: tasks)
        XCTAssertNotNil(factor)
        XCTAssertEqual(factor!, 1.5, accuracy: 0.001)
    }

    func testCalibrationCanBeFilteredByCategory() {
        let work = (0..<6).map { index in
            VaultTask(title: "w\(index)", category: .work, estimatedSeconds: 600, actualSeconds: 900, state: .finished)
        }
        let life = (0..<6).map { index in
            VaultTask(title: "l\(index)", category: .life, estimatedSeconds: 600, actualSeconds: 300, state: .finished)
        }
        XCTAssertEqual(VaultMath.calibrationFactor(tasks: work + life, category: .work)!, 1.5, accuracy: 0.001)
        XCTAssertEqual(VaultMath.calibrationFactor(tasks: work + life, category: .life)!, 0.5, accuracy: 0.001)
    }

    func testNoAdviceWhenEstimatesAreCloseEnough() {
        let tasks = (0..<6).map { index in
            VaultTask(title: "t\(index)", category: .work, estimatedSeconds: 600, actualSeconds: 605, state: .finished)
        }
        XCTAssertNil(VaultMath.calibrationAdvice(tasks: tasks))
    }

    func testAdviceAppearsWhenEstimatesRunLong() {
        let tasks = (0..<6).map { index in
            VaultTask(title: "t\(index)", category: .work, estimatedSeconds: 600, actualSeconds: 900, state: .finished)
        }
        XCTAssertNotNil(VaultMath.calibrationAdvice(tasks: tasks))
    }

    // MARK: - Milestones

    func testMilestonesAreEarnedInOrder() {
        let (earned, next) = VaultMilestone.progress(totalSeconds: 30 * 60)
        XCTAssertEqual(earned.count, 1)
        XCTAssertEqual(earned.first?.id, "m30")
        XCTAssertEqual(next?.id, "m1h")
    }

    func testNoMilestoneAtZero() {
        let (earned, next) = VaultMilestone.progress(totalSeconds: 0)
        XCTAssertTrue(earned.isEmpty)
        XCTAssertEqual(next?.id, "m30")
    }

    func testLastMilestoneHasNoNext() {
        let (earned, next) = VaultMilestone.progress(totalSeconds: 200 * 3600)
        XCTAssertEqual(earned.count, VaultMilestone.all.count)
        XCTAssertNil(next)
    }

    // MARK: - Formatting
    //
    // ⚠️ 这里测的是**格式逻辑**（用哪个单位、怎么切分），不是文案。
    // 文案是翻译，住在 .strings 里；把「1 小时」写死在断言里，
    // 就会在 App 改走本地化的那天集体变红（2026-11-07 实测）。

    func testDurationNeverShowsFractionalHours() {
        // 45 分钟保持 45 分钟，不变成 0.75 小时
        XCTAssertEqual(VaultFormat.components(2700).hours, 0)
        XCTAssertEqual(VaultFormat.components(2700).minutes, 45)
        // 3600 秒 = 整 1 小时，不带残余分钟
        XCTAssertEqual(VaultFormat.components(3600).hours, 1)
        XCTAssertEqual(VaultFormat.components(3600).minutes, 0)
        XCTAssertEqual(VaultFormat.components(3600).seconds, 0)
        // 90 秒 = 1 分 30 秒
        XCTAssertEqual(VaultFormat.components(90).minutes, 1)
        XCTAssertEqual(VaultFormat.components(90).seconds, 30)
        // 30 秒就只显示秒
        XCTAssertEqual(VaultFormat.components(30).seconds, 30)
        XCTAssertEqual(VaultFormat.components(30).minutes, 0)
    }

    func testDurationComponentsHandleOverflowAndNegatives() {
        // 超过 24 小时照样按小时累加，不回绕
        XCTAssertEqual(VaultFormat.components(30 * 3600).hours, 30)
        // 负数当 0 处理，不崩
        XCTAssertEqual(VaultFormat.components(-5).totalSeconds, 0)
        XCTAssertEqual(VaultFormat.components(-5).hours, 0)
    }

    func testCompactDurationUsesTheRightUnit() {
        XCTAssertEqual(VaultFormat.components(3600).hours, 1)
        XCTAssertEqual(VaultFormat.components(3900).hours, 1)
        XCTAssertEqual(VaultFormat.components(3900).minutes, 5)
        XCTAssertEqual(VaultFormat.components(300).minutes, 5)
        XCTAssertEqual(VaultFormat.components(30).seconds, 30)
    }

    func testDurationStringIsNotEmptyAndCarriesTheNumbers() {
        // 文案由 .strings 提供，这里只保证「有内容」且「数字没丢」
        let oneMinute = VaultFormat.duration(60)
        XCTAssertFalse(oneMinute.isEmpty)
        XCTAssertTrue(oneMinute.contains("1"), "时长文案里应有数字 1，实际：\(oneMinute)")

        let twoHours = VaultFormat.duration(7200)
        XCTAssertFalse(twoHours.isEmpty)
        XCTAssertTrue(twoHours.contains("2"), "时长文案里应有数字 2，实际：\(twoHours)")
    }

    func testClockFormat() {
        XCTAssertEqual(VaultFormat.clock(3661), "01:01:01")
        XCTAssertEqual(VaultFormat.clock(-5), "00:00:00")
    }

    // MARK: - Model

    func testTaskDeciationSign() {
        let ahead = VaultTask(title: "a", category: .work, estimatedSeconds: 3600, actualSeconds: 1800, state: .finished)
        XCTAssertEqual(ahead.deviationSeconds, -1800)
        XCTAssertTrue(ahead.isAhead)

        let late = VaultTask(title: "b", category: .work, estimatedSeconds: 3600, actualSeconds: 5400, state: .finished)
        XCTAssertEqual(late.deviationSeconds, 1800)
        XCTAssertFalse(late.isAhead)
    }

    func testUnknownCategoryFallsBackToOther() {
        var task = VaultTask(title: "x", category: .work, estimatedSeconds: 60)
        task.categoryRaw = "nonsense"
        XCTAssertEqual(task.category, .other)
    }
}
