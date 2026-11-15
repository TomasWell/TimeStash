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

    /// 读 App 内某个本地化 key 的当前语言文案（UI test 是独立 target，
    /// 拿不到主 App 的 `L()` 函数，所以自己读 .strings）。
    ///
    /// ⚠️ 2026-11-16 P0：截图里的示例任务名必须跟界面语言一致，
    /// 否则换语言拍商店页时会出现「英文界面夹中文」= 2.3.3 / 2.3.7 风险。
    /// 查不到就退回英文基准（`en.lproj`），**绝不显示 key 本身**。
    ///
    /// ⚠️ 语言码从**启动参数**读（`-TS_SHOT_LANG`），不读环境变量 ——
    /// 实测 `ProcessInfo.environment` 在 XCUITest 里拿不到 xcodebuild
    /// 传下来的环境变量（读到空 → 回落 en → 界面是德语但输入框里是英文）。
    static func shotLanguage() -> String {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-TS_SHOT_LANG"), i + 1 < args.count {
            let v = args[i + 1]
            if !v.isEmpty && !v.hasPrefix("-") { return v }
        }
        return "zh-Hans"
    }

    static func L_forUITest(_ key: String) -> String {
        let i18nDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // TimeStashUITests
            .deletingLastPathComponent()   // ios
            .appendingPathComponent("TimeStash/i18n")
        let lang = shotLanguage()

        // 候选：当前语言 → 去掉地区码 → en
        var candidates = [lang]
        if lang.contains("-") { candidates.append(String(lang.split(separator: "-")[0])) }
        candidates.append("en")

        for loc in candidates {
            let f = i18nDir.appendingPathComponent("\(loc).lproj/Localizable.strings")
            guard let text = try? String(contentsOf: f, encoding: .utf8) else { continue }
            for line in text.components(separatedBy: "\n") {
                let t = line.trimmingCharacters(in: .whitespaces)
                guard t.hasPrefix("\"\(key)\"") else { continue }
                guard let eq = t.firstIndex(of: "=") else { continue }
                let rhs = t[t.index(after: eq)...].trimmingCharacters(in: .whitespaces)
                guard rhs.hasPrefix("\""), rhs.hasSuffix("\";"),
                      rhs.count >= 3 else { continue }
                let value = String(rhs.dropFirst().dropLast(2))
                if !value.isEmpty { return value }
            }
        }
        return key
    }

    /// Where the PNGs land.
    ///
    /// ⚠️ 2026-11-08: this used to write straight into
    /// `store-assets/screenshots` -- the folder that holds the **delivered**
    /// store screenshots. Because this class is part of the UI test target,
    /// every normal test run re-shot them, and on a smaller simulator
    /// (iPhone 15 Pro = 1178x2556) that silently **replaced the shipped
    /// 1290x2796 images with sizes the App Store does not accept**.
    ///
    /// Now the screenshots go to a scratch folder. The official ones are
    /// produced by `scripts/make_store_screenshots.sh`, which pins the
    /// simulator and the output path.
    private static let outputDir = "/Users/mac/TimeStash/.screenshot-work"

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        try? FileManager.default.createDirectory(
            atPath: Self.outputDir,
            withIntermediateDirectories: true
        )
        app = XCUIApplication()
        // 商店页多语言截图：语言由环境变量传入（默认 zh-Hans）。
        //
        // ⚠️ 2026-11-16 P0：原来写死 zh-Hans → 48 个 locale 的商店页
        // 全部共用这一套中文截图（ASC 实测：10 个 checksum 被 48 locale 共用，
        // 零专属图）→ 违反 Guideline 2.3.3（截图须展示该 locale 的实际界面）。
        //
        // ⚠️⚠️ 覆盖语言的参数形式（实测踩了两种错法）：
        //   ① `-AppleLanguages (zh-Hans)`（老式 UserDefaults 写法）→ **无效**，
        //      Bundle.main 的语言协商不认它 → 拍出来仍是中文。
        //   ② 只改系统级 NSGlobalDomain AppleLanguages → **也无效**，
        //      因为 App 用 `NSLocalizedString` 默认 bundle，XCUITest 里
        //      App 进程的环境由测试宿主决定，改全局域不改变它的语言协商。
        //   ✅ **正确形式 = iOS 标准的 `-app_language <code>`**，
        //      且必须作为**真启动参数**传给 App 进程（`launchArguments`），
        //      与 CommutePilot 的成熟做法一致（`simctl launch ... -app_language de`）。
        //
        // ⚠️ `-TS_SHOT_NO_NOTIFICATION` 必须带：系统通知授权弹窗会盖住
        // 整个计时界面（商店页截图 04/10 里能看到那个弹窗）→ 同样违反 2.3.3。
        let lang = Self.shotLanguage()
        app.launchArguments = [
            "-app_language", lang,
            "-TS_SHOT_LANG", lang,
            "-TS_SHOT_NO_NOTIFICATION",
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
        // ⚠️ 2026-11-16 P0：不能写死中文「写周报」——
        // 换语言拍商店页时，这一栏会露出中文 = 英文界面夹中文（2.3.3/2.3.7）。
        // 用与 App 内种子数据同一个本地化键，各语言自动对上。
        titleField.typeText(Self.L_forUITest("demo_task_report"))
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
