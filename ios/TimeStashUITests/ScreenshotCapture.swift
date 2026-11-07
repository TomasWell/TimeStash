import XCTest

/// 商店截图抓取（**不是回归测试**，是产出图片的工具）。
///
/// 做法：XCUITest 精确驱动界面元素 → 每到一步就把 `XCUIScreen.main.screenshot()`
/// 的 PNG 数据写到磁盘。不用坐标点击，因为坐标在不同机型/系统版本上会漂。
///
/// 产物目录：`/Users/mac/TimeStash/store-assets/screenshots/`
///
/// ⚠️ 这个类**不会做任何断言**（它只是截图工具），所以
/// 「测试全绿」在这里不代表功能正确 —— 功能正确由
/// OnboardingUITests / VaultFlowUITests / TabSwitchingUITests 负责。
/// 但每个关键节点仍然用 `waitForExistence` 确认元素真的在，
/// 避免截出一堆空白页。
final class ScreenshotCapture: XCTestCase {

    private static let outputDir = "/Users/mac/TimeStash/store-assets/screenshots"

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        try? FileManager.default.createDirectory(
            atPath: Self.outputDir,
            withIntermediateDirectories: true
        )
        app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(zh-Hans)",
            "-AppleLocale", "zh_CN",
        ]
    }

    /// 把当前屏幕写成 PNG。
    private func capture(_ name: String) {
        let data = XCUIScreen.main.screenshot().pngRepresentation
        let url = URL(fileURLWithPath: Self.outputDir).appendingPathComponent("\(name).png")
        do {
            try data.write(to: url)
            print("[截图] \(url.lastPathComponent) \(data.count) bytes")
        } catch {
            print("[截图失败] \(name): \(error.localizedDescription)")
        }
    }

    /// 引导 4 屏各截一张。
    func testCaptureOnboarding() {
        app.launchArguments.append("-resetOnboarding")
        app.launch()

        let next = app.buttons["onboardingNextButton"]
        XCTAssertTrue(next.waitForExistence(timeout: 25), "引导第 1 屏没出现")
        capture("01-onboarding-problem")

        next.tap()
        XCTAssertTrue(app.buttons["onboardingNextButton"].waitForExistence(timeout: 10), "引导第 2 屏没出现")
        capture("02-onboarding-mechanism")

        app.buttons["onboardingNextButton"].tap()
        let tryButton = app.buttons["onboardingTryButton"]
        XCTAssertTrue(tryButton.waitForExistence(timeout: 12), "引导第 3 屏没出现")
        capture("03-onboarding-try")

        // 第 3 屏点体验 → 计时页也截一张
        tryButton.tap()
        XCTAssertTrue(app.buttons["onboardingFinishButton"].waitForExistence(timeout: 12), "体验计时没开始")
        capture("04-onboarding-timer")

        app.buttons["onboardingFinishButton"].tap()
        XCTAssertTrue(app.buttons["onboardingStartButton"].waitForExistence(timeout: 12), "引导第 4 屏没出现")
        capture("05-onboarding-baseline")
    }

    /// 主界面三屏（收纳箱 / 账本 / 统计）+ 计时页。
    func testCaptureMainScreens() {
        // ⚠️ 主界面截图必须用 `-skipOnboarding`（直接进主界面），
        // **不能**用 `-resetOnboarding` —— 后者会把 hasCompletedOnboarding 写成 false，
        // 于是 App 停在引导页，主界面的 tabBar 永远不出现（2026-11-08 实测）。
        app.launchArguments.append(contentsOf: [
            "-skipOnboarding",
            "-resetVaultData",
            "-seedDemoHistory",
        ])
        app.launch()

        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30), "主界面没出现")
        capture("06-vault-home")

        // 账本 Tab
        let ledgerTab = app.tabBars.buttons.element(boundBy: 1)
        XCTAssertTrue(ledgerTab.waitForExistence(timeout: 10), "账本 Tab 没出现")
        ledgerTab.tap()
        sleep(2)
        capture("07-ledger")

        // 统计 Tab
        let statsTab = app.tabBars.buttons.element(boundBy: 2)
        XCTAssertTrue(statsTab.waitForExistence(timeout: 10), "统计 Tab 没出现")
        statsTab.tap()
        sleep(2)
        capture("08-stats")

        // 回首页，新建任务 → 计时页
        app.tabBars.buttons.element(boundBy: 0).tap()
        sleep(1)
        let startSomething = app.buttons["startSomethingButton"]
        XCTAssertTrue(startSomething.waitForExistence(timeout: 12), "「开始一件事」按钮没出现")
        startSomething.tap()

        let titleField = app.textFields["newTaskTitleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 12), "任务标题输入框没出现")
        titleField.tap()
        titleField.typeText("写周报")
        capture("09-new-task")

        let chip = app.buttons["estimateChip15"]
        XCTAssertTrue(chip.waitForExistence(timeout: 10), "15 分钟快捷按钮没出现")
        chip.tap()

        let create = app.buttons["createAndStartButton"]
        XCTAssertTrue(create.waitForExistence(timeout: 10), "「开始」按钮没出现")
        create.tap()

        XCTAssertTrue(app.staticTexts["timerClock"].waitForExistence(timeout: 20), "计时界面没出现")
        sleep(2)
        capture("10-timer")
    }
}
