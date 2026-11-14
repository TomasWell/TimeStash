import Foundation
import Testing
@testable import TimeStash

/// 界面文案守卫：**不许把本地化 key 直接写进 `Text("...")`**。
///
/// 起因（2026-11-14）：私密记账的「选择日期」整屏显示 `(day)` 占位符，
/// 而 TimeStash 抽查时又发现 **33 处** `Text("ledger_empty_title")` 这类写法
/// —— 界面直接把 key 字符串显示给用户（`ledger_empty_title` 而不是「时间账本」）。
///
/// ⚠️ 关键：SwiftUI 的 `Text("some_key")` 走的是 `LocalizedStringKey` 初始化器，
/// **只有在 key 恰好等于 LocalizedStringKey 时才会查表**；
/// 一旦 key 不在 `.strings` 里，它就**原样显示 key 本身** —— 不崩溃、不告警。
///
/// ⇒ 本守卫做两件事：
/// ① 扫源码：界面层不许出现 `Text("snake_case_key")`（必须走 `L()`）
/// ② 扫 `.strings`：用到的 key 必须真的存在（否则 `L()` 也会原样返回 key）
@Suite("i18n 文案守卫")
struct LocalizationGuardTests {

    /// 源码根目录（本测试 target 与源码同级）
    private var sourceRoot: URL {
        // .../ios/TimeStashTests/LocalizationGuardTests.swift → .../ios/TimeStash
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // TimeStashTests
            .deletingLastPathComponent()   // ios
            .appendingPathComponent("TimeStash")
    }

    /// 收集源码里所有 `Text("...")` 的字面量参数
    private func literalTextKeys() -> [(file: String, line: Int, key: String)] {
        var out: [(String, Int, String)] = []
        guard let enumerator = FileManager.default.enumerator(
            at: sourceRoot, includingPropertiesForKeys: nil
        ) else { return out }

        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let path = url.path
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let lines = text.components(separatedBy: "\n")
            for (idx, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                // 跳过注释
                if trimmed.hasPrefix("//") || trimmed.hasPrefix("*") { continue }
                // 匹配 Text("literal") —— 只取 snake_case 形态（本地化 key 的特征）
                let pattern = #"Text\(\s*"([a-z][a-z0-9]*_[a-z0-9_]+)"\s*\)"#
                guard let re = try? NSRegularExpression(pattern: pattern) else { continue }
                let ns = line as NSString
                for match in re.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
                    guard let r = Range(match.range(at: 1), in: line) else { continue }
                    out.append((url.lastPathComponent, idx + 1, String(line[r])))
                }
            }
        }
        return out
    }

    /// 读取某个 locale 的 Localizable.strings 里所有 key
    private func keys(inLocalizationDirectory dir: URL) -> Set<String> {
        var keys = Set<String>()
        for file in ["Localizable.strings", "InfoPlist.strings"] {
            let url = dir.appendingPathComponent(file)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            // "key" = "value";
            let pattern = #"\"([A-Za-z0-9_]+)\"\s*=\s*\"[^\"]*\"\s*;"#
            guard let re = try? NSRegularExpression(pattern: pattern) else { continue }
            let ns = text as NSString
            for match in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                guard let r = Range(match.range(at: 1), in: text) else { continue }
                keys.insert(String(text[r]))
            }
        }
        return keys
    }

    /// ① 界面层不许把 key 直接写进 Text()
    @Test("界面层不许出现 Text(\"snake_case_key\") —— 必须走 L()")
    func noLiteralLocalizationKeysInText() {
        let hits = literalTextKeys()
        if !hits.isEmpty {
            let detail = hits
                .map { "\($0.file):\($0.line)  Text(\"\($0.key)\")" }
                .joined(separator: "\n    ")
            Issue.record("界面层有 \(hits.count) 处直接显示本地化 key（用户会看到 key 本身）：\n    \(detail)")
        }
    }

    /// ② 用到的 key 必须真的在 .strings 里（否则 L() 也原样返回 key）
    @Test("L() 用到的 key 必须存在于 Localizable.strings")
    func allUsedKeysExistInStrings() throws {
        // 本地化目录：TimeStash/i18n/*.lproj（xcodegen 的 resources 段指向它）
        // 兼容不同目录布局：找所有 .lproj 所在处
        var candidates: [URL] = []
        if let enumerator = FileManager.default.enumerator(at: sourceRoot, includingPropertiesForKeys: nil) {
            for case let url as URL in enumerator where url.pathExtension == "lproj" {
                candidates.append(url)
            }
        }
        guard !candidates.isEmpty else {
            Issue.record("找不到任何 .lproj 目录（路径可能变了）：\(sourceRoot.path)")
            return
        }
        // 以 zh-Hans 为基准（key 集合应与其它 locale 一致）
        // ⚠️ 排除 Widget 的 i18n（独立 target，用 LocalizedStringKey 写法，不需要 L()）
        let appCandidates = candidates.filter { $0.path.contains("/TimeStash/i18n/") }
        let pool = appCandidates.isEmpty ? candidates : appCandidates
        let zh = pool.first { $0.lastPathComponent == "zh-Hans.lproj" } ?? pool[0]
        let available = keys(inLocalizationDirectory: zh)
        #expect(!available.isEmpty, "Localizable.strings 一个 key 都没解析到 —— 解析器坏了")

        // 扫源码里所有 L("key") 调用
        var used = Set<String>()
        if let enumerator = FileManager.default.enumerator(at: sourceRoot, includingPropertiesForKeys: nil) {
            for case let url as URL in enumerator where url.pathExtension == "swift" {
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                let pattern = #"\bL\(\s*\"([A-Za-z0-9_]+)\""#
                guard let re = try? NSRegularExpression(pattern: pattern) else { continue }
                let ns = text as NSString
                for match in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                    guard let r = Range(match.range(at: 1), in: text) else { continue }
                    used.insert(String(text[r]))
                }
            }
        }
        let missing = used.subtracting(available).sorted()
        if !missing.isEmpty {
            Issue.record("L() 用了 \(missing.count) 个 .strings 里不存在的 key（界面会显示 key 本身）：\n    \(missing.joined(separator: "\n    "))")
        }
    }
}
