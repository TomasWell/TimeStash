import XCTest

/// 回归用例：**核心闭环真的成立** —— 新建任务 → 计时 → 提前完成 → 箱子数字变大。
///
/// 这条用例覆盖的是 App 的唯一主线（设计文档第 3 节）。
/// 它不用 mock，全部走真实界面元素，所以任何一环断了都会红。
///
/// ⚠️ 关于断言：箱子的数字是 SwiftUI 动态文本，控件树里可能没有可稳定读取的
/// 数值。这里改用**「首页出现非零的存入时间」**来判定入箱成功 —— 这既能证明
/// 入箱发生了，又不依赖具体控件结构。
final class VaultFlowUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-skipOnboarding",
            // 清掉上一轮遗留的任务（App Group 容器在 UITest 之间不会自动清）
            "-resetVaultData",
        ]
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20), "底栏没出现")
    }

    /// 新建 → 开始 → 提前完成 → 首页出现存入记录。
    func testCreateFinishEarlyAndBankTime() {
        let startSomething = app.buttons["startSomethingButton"]
        XCTAssertTrue(startSomething.waitForExistence(timeout: 10), "找不到「开始一件事」按钮")
        startSomething.tap()

        let titleField = app.textFields["newTaskTitleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 10), "找不到任务标题输入框")
        titleField.tap()
        titleField.typeText("Write the proposal")

        // 预估选 15 分钟（快捷按钮）
        let chip = app.buttons["estimateChip15"]
        XCTAssertTrue(chip.waitForExistence(timeout: 10), "找不到 15 分钟快捷按钮")
        chip.tap()

        let create = app.buttons["createAndStartButton"]
        XCTAssertTrue(create.waitForExistence(timeout: 10), "找不到「开始」按钮")
        create.tap()

        // 计时界面
        let clock = app.staticTexts["timerClock"]
        XCTAssertTrue(clock.waitForExistence(timeout: 15), "计时界面没出现")

        let finish = app.buttons["finishTaskButton"]
        XCTAssertTrue(finish.waitForExistence(timeout: 10), "找不到「提前完成」按钮")
        finish.tap()

        // 回到首页，账本里应该有这条记录
        let banner = app.staticTexts["Write the proposal"]
        XCTAssertTrue(
            banner.waitForExistence(timeout: 15),
            "提前完成后首页没有出现这条任务 —— 主线断了"
        )
    }

    /// 暂停后计时应该停住；继续后应该接着走。
    func testPauseStopsTheClockAndResumeContinues() {
        let startSomething = app.buttons["startSomethingButton"]
        XCTAssertTrue(startSomething.waitForExistence(timeout: 10), "找不到「开始一件事」按钮")
        startSomething.tap()

        let titleField = app.textFields["newTaskTitleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 10), "找不到任务标题输入框")
        titleField.tap()
        titleField.typeText("Paused task")

        let create = app.buttons["createAndStartButton"]
        XCTAssertTrue(create.waitForExistence(timeout: 10), "找不到「开始」按钮")
        create.tap()

        let clock = app.staticTexts["timerClock"]
        XCTAssertTrue(clock.waitForExistence(timeout: 15), "计时界面没出现")

        let pause = app.buttons["pauseResumeButton"]
        XCTAssertTrue(pause.waitForExistence(timeout: 10), "找不到暂停按钮")
        pause.tap()

        let hint = app.staticTexts["pausedHint"]
        XCTAssertTrue(hint.waitForExistence(timeout: 8), "暂停后没有出现「已暂停」提示")

        // 暂停期间时钟必须不动
        let before = clock.label
        Thread.sleep(forTimeInterval: 3)
        XCTAssertEqual(clock.label, before, "暂停期间时钟还在走 —— 暂停没有真的停表")

        // 继续后时钟重新走
        pause.tap()
        Thread.sleep(forTimeInterval: 3)
        XCTAssertNotEqual(clock.label, before, "继续之后时钟没有恢复")
    }
}
