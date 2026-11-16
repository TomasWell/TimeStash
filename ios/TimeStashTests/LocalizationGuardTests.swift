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
                // ⚠️ 2026-11-16 P0 扩面：原来只扫 `Text("literal")`，
                // 漏掉了 `Button("literal")` / `Label("literal")` —— 而这两个
                // 同样是 LocalizedStringKey 初始化器，查不到 key 就显示 key 原文。
                // 实证：LedgerView 的筛选菜单 `Button("category_\(c.rawValue)")`
                // 在所有语言下都显示 `category_work` 原文（11-14 那次 33 处修复漏网）。
                let pattern = #"(?:Text|Button|Label|TextField|Toggle|Link|Picker)\(\s*"([a-z][a-z0-9]*_[a-z0-9_]+)"\s*\)"#
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

    /// ③ 界面层不许「运行时拼 key」—— `Button("category_\(rawValue)")`
    ///
    /// 起因（2026-11-16 P0 机械取证）：筛选菜单用
    /// `Button("category_\(c.rawValue)")` → SwiftUI 把它当 LocalizedStringKey，
    /// 查表用的是**格式串** `category_%` → 查不到 → **所有语言下都显示
    /// `category_work` 原文**（11-14 那次「33 处界面显示 key」的修复漏掉了它，
    /// 因为那次守卫只扫 `Text("字面量")`）。
    ///
    /// 判据：字面量里出现 `snake_case_` 前缀**且**后面跟着插值 → 一定是拼 key。
    @Test("界面层不许运行时拼 key（Button/Label/Text(\"prefix_\\(...)））")
    func noRuntimeBuiltLocalizationKeys() {
        // 只在主 App 目录扫（Widget 是独立 target，没有 L()，写法合法）
        let components = ["Text", "Button", "Label", "TextField", "Toggle", "Link", "Picker"]
        let componentPattern = components.joined(separator: "|")
        // 字面量里先出现 `word_`，后面又有插值 → 拼 key
        let pattern = "(?:\(componentPattern))\\(\\s*\"([a-z][a-z0-9]*_[^\"]*\\\\\\()"

        var hits: [String] = []
        if let enumerator = FileManager.default.enumerator(
            at: sourceRoot, includingPropertiesForKeys: nil
        ) {
            for case let url as URL in enumerator where url.pathExtension == "swift" {
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                for (idx, line) in text.components(separatedBy: "\n").enumerated() {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.hasPrefix("//") || trimmed.hasPrefix("*") { continue }
                    guard let re = try? NSRegularExpression(pattern: pattern) else { continue }
                    let ns = line as NSString
                    for match in re.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
                        hits.append("\(url.lastPathComponent):\(idx + 1)  \(trimmed)")
                    }
                }
            }
        }
        if !hits.isEmpty {
            Issue.record("界面层有 \(hits.count) 处运行时拼 key（界面会显示 key 原文）：\n    \(hits.joined(separator: "\n    "))")
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
        // ⚠️⚠️ 2026-11-16 P0：必须**跳过注释行**（与本文件上面两个守卫一致）。
        //   起因：本守卫报了一个**不存在的缺键** `event_wake` —— 那不是代码，
        //   是 DemoSeed.swift 里的一句文档注释「（`L("event_wake")`）」，
        //   指的是 CommutePilot 的同类写法。
        //   ⚠️ 为什么这条必须修而不能忽略：
        //   **假阳性会逼人「把 key 从 .strings 里删掉」来让守卫变绿**
        //   —— 那等于为了过检查而破坏真实文案（另一个守卫明令禁止）。
        //   ⇒ 守卫只查**代码**，不查注释。
        var used = Set<String>()
        let callPattern = #"\bL\(\s*\"([A-Za-z0-9_]+)\""#
        guard let callRe = try? NSRegularExpression(pattern: callPattern) else { return }
        if let enumerator = FileManager.default.enumerator(at: sourceRoot, includingPropertiesForKeys: nil) {
            for case let url as URL in enumerator where url.pathExtension == "swift" {
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                for line in text.components(separatedBy: "\n") {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    // 跳过注释行（// 与 /// 与 /* */ 块的行首 * ）
                    if trimmed.hasPrefix("//") || trimmed.hasPrefix("*") { continue }
                    let ns = line as NSString
                    for match in callRe.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
                        guard let r = Range(match.range(at: 1), in: line) else { continue }
                        used.insert(String(line[r]))
                    }
                }
            }
        }
        let missing = used.subtracting(available).sorted()
        if !missing.isEmpty {
            Issue.record("L() 用了 \(missing.count) 个 .strings 里不存在的 key（界面会显示 key 本身）：\n    \(missing.joined(separator: "\n    "))")
        }
    }
}
