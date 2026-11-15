import XCTest
import Foundation
@testable import TimeStash

/// **巡检调试入口的守卫测试。**
///
/// ⚠️ 为什么需要（CommutePilot 2026-11-10 教训）：
/// sweep 脚本报「✅ 全过」，但所有屏截的都是同一个界面 ——
/// OCR 全绿、报告好看，而目标界面一个都没打开。
///
/// 这里堵两个口子：
/// ① 页面清单里用到的路由名，App 必须认识（名字写错 = 那一屏永远截不到）；
/// ② App 认识的每个路由名，页面清单里都要用（清单漏了 = 那屏从没被看过）。
final class DebugShotRouteGuardTests: XCTestCase {

    /// 仓库根目录（本文件在 ios/TimeStashTests/ 下）。
    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // TimeStashTests
            .deletingLastPathComponent()   // ios
            .deletingLastPathComponent()   // TimeStash (repo root)
    }

    /// 页面清单里的每个路由名都必须被 App 认识。
    func testSweepPageListOnlyUsesKnownRoutes() throws {
        let pagesFile = Self.repoRoot.appendingPathComponent("scripts/page_sweep/pages.txt")
        guard FileManager.default.fileExists(atPath: pagesFile.path) else {
            XCTFail("页面清单还没建：\(pagesFile.path)")
            return
        }
        let text = try String(contentsOf: pagesFile, encoding: .utf8)

        var seenPages = 0
        var usedRoutes: Set<String> = []
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            seenPages += 1
            // 行格式：名字|启动参数|关键词。参数在第二段（整段拆开，
            // 否则第三列关键词会和最后一个参数粘成一个 token）。
            let cols = trimmed.split(separator: "|").map(String.init)
            let argsText = cols.count > 1 ? cols[1] : ""
            let tokens = argsText.split(separator: " ").map(String.init)
            for (i, token) in tokens.enumerated() where token == DebugShot.routeFlag {
                guard i + 1 < tokens.count else {
                    XCTFail("pages.txt 里 \(trimmed) 的 \(DebugShot.routeFlag) 后面没跟路由名")
                    continue
                }
                let route = String(tokens[i + 1])
                usedRoutes.insert(route)
                XCTAssertTrue(DebugShot.knownRoutes.contains(route),
                              "pages.txt 用了 App 不认识的路由 \(route) —— 那一屏永远截不到。" +
                              "修法：把 \(route) 加进 DebugShot.knownRoutes 并在对应界面里接上。")
            }
        }
        XCTAssertGreaterThan(seenPages, 0, "pages.txt 里一行页面都没有")
    }

    /// App 认识的每个路由都要出现在页面清单里（不然那屏从没被巡检过）。
    func testEveryKnownRouteIsSwept() throws {
        let pagesFile = Self.repoRoot.appendingPathComponent("scripts/page_sweep/pages.txt")
        guard FileManager.default.fileExists(atPath: pagesFile.path) else {
            XCTFail("页面清单还没建：\(pagesFile.path)")
            return
        }
        let text = try String(contentsOf: pagesFile, encoding: .utf8)
        let used = text.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .flatMap { line -> [String] in
                let cols = line.split(separator: "|").map(String.init)
                let argsText = cols.count > 1 ? cols[1] : ""
                let tokens = argsText.split(separator: " ").map(String.init)
                return tokens.enumerated()
                    .filter { $0.element == DebugShot.routeFlag }
                    .compactMap { $0.offset + 1 < tokens.count ? String(tokens[$0.offset + 1]) : nil }
            }
        for route in DebugShot.knownRoutes.sorted() {
            XCTAssertTrue(used.contains(route),
                          "路由 \(route) 在 App 里登记了，但 pages.txt 没用它 —— 这屏从没被巡检过。" +
                          "修法：在 pages.txt 加一行，或从 knownRoutes 删掉。")
        }
    }

    /// 解析器必须把「下一个 flag」当成 flag 而不是值。
    ///
    /// `-TS_SHOT_ROUTE -skipOnboarding` 这种写法会让路由值变成
    /// "-skipOnboarding"，App 打开默认页，而 sweep 报「✅ 全过」。
    func testValueParserRejectsNextFlagAsValue() {
        XCTAssertNil(DebugShot.value(of: DebugShot.routeFlag,
                                     in: ["-TS_SHOT_ROUTE", "-skipOnboarding"]))
        XCTAssertNil(DebugShot.value(of: DebugShot.routeFlag, in: ["-TS_SHOT_ROUTE"]))
        XCTAssertEqual(DebugShot.value(of: DebugShot.routeFlag,
                                       in: ["-TS_SHOT_ROUTE", "vault"]), "vault")
        XCTAssertNil(DebugShot.value(of: DebugShot.routeFlag, in: []))
    }

    /// 引导页码越界要夹住：onboarding9 不能让 tag 指到不存在的页。
    func testOnboardingPageIndexClamped() {
        XCTAssertEqual(DebugShot.onboardingPageIndex(for: "onboarding0"), 0)
        XCTAssertEqual(DebugShot.onboardingPageIndex(for: "onboarding3"), 3)
        XCTAssertEqual(DebugShot.onboardingPageIndex(for: "onboarding9"), 3)
        XCTAssertEqual(DebugShot.onboardingPageIndex(for: "vault"), 0)
        XCTAssertEqual(DebugShot.onboardingPageIndex(for: nil), 0)
        XCTAssertEqual(DebugShot.onboardingPageIndex(for: "onboarding"), 0)
        XCTAssertEqual(DebugShot.onboardingPageIndex(for: "onboardingX"), 0)
    }
}
