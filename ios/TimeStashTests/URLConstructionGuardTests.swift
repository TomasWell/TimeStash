import XCTest
import Foundation

/// URL 构造守卫（2026-11-11 用户拍板铺到全部 App）
///
/// 起因：私密记账 1.0.18 在 iOS 16 设备「打开即崩」——
/// `URL(string: "mailto:...?subject=\(L("app_name"))%20Feedback")!` 强制解包。
/// Apple 在 iOS 17 改用 RFC 3986（自动百分号编码非法字符），
/// iOS 16 及更早仍按旧 RFC 1738/1808，遇到非 ASCII 直接返回 nil → 崩溃。
///
/// 规则（全部 App 适用）：
///   ① 源码里不许出现 `URL(string: ...)!` 强制解包
///   ② 本地化文案（L("...")）不许直接拼进 `URL(string:)`
///   ③ 本地化文案要进 query，必须走 URLComponents + percentEncodedQuery
final class URLConstructionGuardTests: XCTestCase {
    /// 被测源码根目录：本文件在 <App>Tests/ 下，往上一级就是源码根
    private var sourceRoot: URL {
        URL(fileURLWithPath: #filePath)          // .../<App>Tests/URLConstructionGuardTests.swift
            .deletingLastPathComponent()         // .../<App>Tests
            .deletingLastPathComponent()         // .../（源码根）
    }

    private func swiftSources() -> [URL] {
        guard let e = FileManager.default.enumerator(
            at: sourceRoot, includingPropertiesForKeys: nil) else { return [] }
        var out: [URL] = []
        for case let f as URL in e where f.pathExtension == "swift" {
            let p = f.path
            if p.contains("/DerivedData/") || p.contains("/.build/") || p.contains("/SourcePackages/") { continue }
            // ⛔ 必须跳过**测试目录**，否则这个守卫会把自己扫进去：
            //    断言消息里写着字面量 `URL(string: ...)!`，
            //    会被自己的正则匹配上 → 每次都误报「源码里有强制解包」。
            //    （2026-11-11 实测：TimeStash 首次跑这个守卫就是被自己误报卡红的，
            //      而产品代码里其实一处都没有。）
            //    守卫的对象是**产品代码**——测试代码里的 URL 构造不会让用户崩溃。
            if p.contains("/Tests/") || p.contains("/UITests/") || p.hasSuffix("Tests.swift") { continue }
            out.append(f)
        }
        return out
    }

    func testNoForceUnwrappedURLString() throws {
        var offenders: [String] = []
        let re = try NSRegularExpression(pattern: #"URL\s*\(\s*string:[^)]*\)\s*!"#)
        for f in swiftSources() {
            let text = try String(contentsOf: f, encoding: .utf8)
            for (n, line) in text.components(separatedBy: .newlines).enumerated() {
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("//") || t.hasPrefix("///") || t.hasPrefix("*") { continue }
                if re.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil {
                    offenders.append("\(f.lastPathComponent):\(n + 1)  \(t)")
                }
            }
        }
        XCTAssertTrue(offenders.isEmpty,
            "源码里不许再出现 `URL(string: ...)!` 强制解包（iOS 16 会崩）：\n" + offenders.joined(separator: "\n"))
    }

    func testNoLocalizedTextDirectlyInURLString() throws {
        var offenders: [String] = []
        let re = try NSRegularExpression(pattern: #"URL\s*\(\s*string:[^)]*L\(\s*\""#)
        for f in swiftSources() {
            let text = try String(contentsOf: f, encoding: .utf8)
            for (n, line) in text.components(separatedBy: .newlines).enumerated() {
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("//") || t.hasPrefix("///") || t.hasPrefix("*") { continue }
                if re.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil {
                    offenders.append("\(f.lastPathComponent):\(n + 1)  \(t)")
                }
            }
        }
        XCTAssertTrue(offenders.isEmpty,
            "本地化文案不许直接拼进 URL(string:)（非 ASCII 在 iOS 16 返回 nil）：\n" + offenders.joined(separator: "\n"))
    }
}
