#!/usr/bin/env python3
"""更新 UNRESOLVED.md：私密记账线上崩溃条目已定案（2026-11-11）。"""
import io

P = "/Users/mac/.hermes/UNRESOLVED.md"

OLD_TITLE = ("### [上架] 私密记账 1.0.17（build 28）线上「打开就崩」—— "
             "兜底已上线(1.0.18审核中)，根因待真机自证（2026-11-09 报障）")
NEW_TITLE = ("### [已解决·待 1.0.20 过审] 私密记账线上「打开就崩」—— "
             "根因已定案（iOS 16 上 URL 强制解包）（2026-11-09 报障，11-11 定案）")

ADDITION = """
- **2026-11-11 17:5x 用户提供了真机崩溃日志 → 根因定案**：
  - 崩溃包：1.0.18 / build 29 / iPhone14,8（iPhone 13）/ **iOS 16.1** /
    EXC_BREAKPOINT / SIGTRAP / 启动后 **162 毫秒**就崩。
  - **符号化**：用 build 29 的 dSYM（UUID 与用户机器上的 binary 完全一致，已核）
    + `atos` 解析 → 精确落在 **`SettingsView` 的 body 闭包**，
    对应源码 `Link(destination: URL(string: "mailto:...?subject=\\(L("app_name"))%20Feedback")!)`。
  - **根因（Apple 官方文档 `URL.init(string:)`）**：iOS 17+ 的 `URL` 解析改成 RFC 3986，
    **自动 percent/IDNA 编码非法字符**；**iOS 16 及更早仍是旧 RFC 1738/1808，
    遇到非 ASCII 直接返回 nil**。中文下 `L("app_name")` = 私密记账 →
    `URL(string:)` 返回 nil → `!` 强制解包 → **Swift trap → 打开即崩**。
  - **为什么之前四轮排查都没抓到**：① 模拟器只有 iOS 17.4/17.5/18.2/26.2，
    **全在新解析行为之上**（Xcode 26.2 已不再提供 iOS 16 runtime，本地无法复现）；
    ② 这行老代码从 build 27 就有，但 build 27 要求 iOS 17，iOS 16 用户装不上；
    ③ build 28 把 deploymentTarget 降到 15.0，**iOS 16 用户第一次装得上 → 第一次启动就崩**。
  - **修复（1.0.20 / build 31）**：改用 `URLComponents` 显式构造（自己百分号编码，
    任何系统版本对非 ASCII 都安全）且**不强制解包**；新增 3 项回归测试
    （46 个 locale 的 app_name 都能构造出安全 URL、构造器非 nil、源码里不许再有 `URL(string:)!`）。
    1165/1165 测试全绿。
  - **状态**：1.0.20 已于 2026-11-11 18:24 提交 Apple 审核（WAITING_FOR_REVIEW，
    AFTER_APPROVAL 过审自动上架）；build 31 同时在 TestFlight 内部测试组（用户可自行安装验证）。
  - **顺带扫出的隐患（未处理，次要）**：`ScreenshotSeed.profile(for:)` 里有
    `profiles[language] ?? profiles[profileAliases[language] ?? "en"]!`，
    若 `profiles` 表里没有 "en" 键会 trap —— 但只在商店截图开关打开时触发，
    普通用户走不到。**待办：给 `profiles` 补 "en" 键或去掉强制解包。**

"""

MARKER = "\n## 已解决\n"


def main():
    with io.open(P, encoding="utf-8") as f:
        s = f.read()

    changed = []
    if OLD_TITLE in s:
        s = s.replace(OLD_TITLE, NEW_TITLE)
        changed.append("标题")
    if "2026-11-11 17:5x 用户提供了真机崩溃日志" not in s and MARKER in s:
        s = s.replace(MARKER, ADDITION + MARKER, 1)
        changed.append("进展")
    with io.open(P, "w", encoding="utf-8") as f:
        f.write(s)
    print("已更新:", changed or "无变化")


if __name__ == "__main__":
    main()
