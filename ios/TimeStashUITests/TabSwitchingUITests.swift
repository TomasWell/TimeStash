import XCTest

/// 回归用例：**三个 tab 真的能切过去**。
///
/// 背景（HabitFlow 2026-11-07 实测的同型事故）：App 用
/// `TabView(selection: Binding(get: { 常量 }, set: { _ in }))`，
/// setter 不写任何状态 → 用户点「统计」时界面立刻弹回第一个 tab，
/// 用户永远切不过去。
///
/// 而当时的 UI 测试只是 **print 一句就跳过**，不报错 → 缺陷全绿放过。
/// 所以这里必须：① 真的点；② 断言目标页出现；③ 静置后再断言一次，
/// 确认页面没有被弹回去。
final class TabSwitchingUITests: XCTestCase {

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

    /// 点「时间账本」→ 账本页真的出现。
    func testTappingLedgerTabShowsLedgerScreen() {
        let ledgerTab = app.tabBars.buttons["Ledger"]
        XCTAssertTrue(ledgerTab.waitForExistence(timeout: 10), "找不到 Ledger 标签")
        ledgerTab.tap()

        XCTAssertTrue(
            app.navigationBars["Ledger"].waitForExistence(timeout: 10),
            "点了 Ledger 标签但账本页没出现 —— tab 切换失效"
        )

        // 静置后再断言：排除转场动画期间两个页面短暂同时存在的假阳性
        Thread.sleep(forTimeInterval: 2.0)
        XCTAssertTrue(app.navigationBars["Ledger"].exists, "静置 2 秒后账本页消失了 —— tab 被弹回去了")
        XCTAssertFalse(app.navigationBars["Vault"].exists, "点了 Ledger 之后首页还在 —— 断言判据本身失效")
    }

    /// 点「统计」→ 统计页真的出现。
    func testTappingStatsTabShowsStatsScreen() {
        let statsTab = app.tabBars.buttons["Stats"]
        XCTAssertTrue(statsTab.waitForExistence(timeout: 10), "找不到 Stats 标签")
        statsTab.tap()

        XCTAssertTrue(
            app.navigationBars["Stats"].waitForExistence(timeout: 10),
            "点了 Stats 标签但统计页没出现 —— tab 切换失效"
        )

        Thread.sleep(forTimeInterval: 2.0)
        XCTAssertTrue(app.navigationBars["Stats"].exists, "静置 2 秒后统计页消失了 —— tab 被弹回去了")
    }

    /// 来回切都要能用。
    func testCanSwitchBackToVaultTab() {
        let statsTab = app.tabBars.buttons["Stats"]
        XCTAssertTrue(statsTab.waitForExistence(timeout: 10), "找不到 Stats 标签")
        statsTab.tap()
        XCTAssertTrue(app.navigationBars["Stats"].waitForExistence(timeout: 10), "没切到统计页")

        let vaultTab = app.tabBars.buttons["Vault"]
        XCTAssertTrue(vaultTab.waitForExistence(timeout: 10), "找不到 Vault 标签")
        vaultTab.tap()
        XCTAssertTrue(app.navigationBars["Vault"].waitForExistence(timeout: 10), "没切回收纳箱 —— tab 切换失效")
    }
}
