#!/usr/bin/env python3
"""把 iOS 16 模拟器的测试环境两个坑写进 colorfuledger skill（2026-11-11）。"""
import io

P = "/Users/mac/.hermes/skills/colorfuledger/SKILL.md"

ANCHOR = "### ⛔⭐⭐ 复现要用 **Release 模拟器产物**，Debug 的二进制是 stub"

ADDITION = """### ⛔⭐⭐ iOS 16 模拟器上的**测试环境**两个坑（2026-11-11 踩完）

**坑 1：改模拟器语言后必须重启模拟器，否则测试结果没有意义**

`xcrun simctl spawn <udid> defaults write NSGlobalDomain AppleLanguages -array zh-Hans`
改的是**系统偏好**，但 `Locale.preferredLanguages` 在**进程启动时**就被缓存，
SpringBoard 仍持有旧值 → `LanguageManager.bestMatchForSystemLanguage()` 按旧语言选 bundle
→ `L("book_default_name")` 返回中文「默认账本」→ `MultiBookTests.defaultBookDisplayNameIsLocalized`
在 **iOS 16.4 上失败、在 iOS 17.4 上通过** —— 看起来像「iOS 16 特有 bug」，其实是环境问题。

⚠️ **差点误判成产品 bug**。判据：
- 对照组（iOS 17.4 同用例）通过 → 先怀疑环境，别急着改代码
- 把模拟器关掉并抹掉后重跑 → 通过 ⇒ 是环境

⇒ **改语言后要「关掉 → 抹掉 → 重启」才算干净**
（`simctl erase` 会清掉全部设置，语言回跟随宿主机 macOS；本机是 zh-Hans-CN，
  `bestMatchForSystemLanguage()` 走 prefix 分支 → zh-Hans → 全量 1165 用例仍全绿。）

**坑 2：`-only-testing` 对 Swift Testing 的函数名过滤器常常匹配不到 → 静默「Executed 0 tests」**

`-only-testing:ColorFuLedgerTests/MultiBookTests/defaultBookDisplayNameIsLocalized`
→ `Executed 0 tests` + `** TEST SUCCEEDED **` = **假成功**。
⇒ 用 **suite 级**过滤器 `-only-testing:ColorFuLedgerTests/MultiBookTests`；
  Swift Testing 的用例数看 `✔ Test run with N tests in M suites passed`，
  **别看 XCTest 的 `Executed N tests`**（Swift Testing 的用例不计入那个数）。

**⭐ 结论：iOS 16.4 上全量 1165 个用例全绿、无崩溃。**
（iOS 16.4 runtime + 模拟器 UDID `E4D10850-FEEF-44F0-A251-70AD5841D0BE`，
  `DEV=<udid> bash scripts/run_tests.sh` 可直接跑全量。）

""" + ANCHOR


def main():
    with io.open(P, encoding="utf-8") as f:
        s = f.read()
    if "iOS 16 模拟器上的**测试环境**两个坑" in s:
        print("已存在，跳过")
        return
    if ANCHOR not in s:
        print("FAIL: 锚点没找到")
        return
    s = s.replace(ANCHOR, ADDITION, 1)
    with io.open(P, "w", encoding="utf-8") as f:
        f.write(s)
    print("OK: 已写入 iOS 16 测试环境两坑")


if __name__ == "__main__":
    main()
