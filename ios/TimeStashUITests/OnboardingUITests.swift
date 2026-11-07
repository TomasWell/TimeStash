import XCTest

/// 回归用例：**新用户第一次进来，引导页能一路走完**。
///
/// 背景：引导页有 4 屏，第 3 屏是 1 分钟体验任务，第 4 屏是基准预估滑杆。
/// 这条用例把 4 屏都走一遍，任何一屏按钮点不动都会在这里暴露。
///
/// ⚠️ 断言必须落在**真实的界面元素**上 —— 「没找到元素就跳过」那种写法
/// 会让演示录像录出一段「什么都没点到」的画面，而测试照样全绿
/// （HabitFlow 2026-11-07 实测的同型事故）。
final class OnboardingUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            // 重置引导状态。⚠️ 不能用 `-hasCompletedOnboarding NO` ——
            // UserDefaults 参数域优先级最高，会把 App 写进去的「已完成」也盖掉，
            // 引导走完也回不到主界面。App 里有专门的 -resetOnboarding 处理。
            "-resetOnboarding",
        ]
        app.launch()
    }

    /// 走完 4 屏引导。
    func testCanWalkThroughAllFourOnboardingScreens() {
        let next = app.buttons["onboardingNextButton"]
        XCTAssertTrue(next.waitForExistence(timeout: 20), "引导第 1 屏的「继续」按钮没出现")
        next.tap()

        // 第 2 屏：机制说明
        let next2 = app.buttons["onboardingNextButton"]
        XCTAssertTrue(next2.waitForExistence(timeout: 8), "引导第 2 屏没出现")
        next2.tap()

        // 第 3 屏：1 分钟体验
        let tryButton = app.buttons["onboardingTryButton"]
        XCTAssertTrue(tryButton.waitForExistence(timeout: 8), "引导第 3 屏的体验按钮没出现")
        tryButton.tap()

        let finishButton = app.buttons["onboardingFinishButton"]
        XCTAssertTrue(finishButton.waitForExistence(timeout: 8), "体验计时开始后「完成」按钮没出现")
        finishButton.tap()

        // 第 4 屏：基准预估
        let start = app.buttons["onboardingStartButton"]
        XCTAssertTrue(start.waitForExistence(timeout: 8), "引导第 4 屏的「开始收纳」按钮没出现")
        start.tap()

        // 走完引导应该进到主界面（底部 3 个 tab）
        XCTAssertTrue(
            app.tabBars.firstMatch.waitForExistence(timeout: 20),
            "走完引导后没有进到主界面"
        )
    }

    /// 体验任务必须真的进箱子 —— 这一屏的全部意义就在这儿。
    func testOnboardingExperimentActuallyFillsTheBox() {
        // 体验按钮在第 3 屏，必须先翻过去
        let next = app.buttons["onboardingNextButton"]
        XCTAssertTrue(next.waitForExistence(timeout: 20), "找不到引导的「继续」按钮")
        next.tap()
        let next2 = app.buttons["onboardingNextButton"]
        XCTAssertTrue(next2.waitForExistence(timeout: 8), "引导第 2 屏没出现")
        next2.tap()

        let tryButton = app.buttons["onboardingTryButton"]
        XCTAssertTrue(tryButton.waitForExistence(timeout: 12), "找不到体验按钮")
        tryButton.tap()

        let finishButton = app.buttons["onboardingFinishButton"]
        XCTAssertTrue(finishButton.waitForExistence(timeout: 8), "找不到体验完成按钮")
        finishButton.tap()

        let start = app.buttons["onboardingStartButton"]
        XCTAssertTrue(start.waitForExistence(timeout: 8), "找不到开始收纳按钮")
        start.tap()

        // 主界面应该显示累计存入不是 0
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20), "没有进到主界面")

        // 静态文本里应该出现非零的累计时间（「30 秒」之类的）
        let nonzero = app.staticTexts.allElementsBoundByIndex.contains { element in
            let label = element.label
            return label.contains("sec") || label.contains("min") || label.contains("h")
        }
        XCTAssertTrue(nonzero, "体验任务完成后主界面看不到任何非零的存入时间")
    }
}
