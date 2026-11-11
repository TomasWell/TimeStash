#!/usr/bin/env python3
"""记录两条：① TabView + if #available 的隐蔽坑（写进 skill）
② HabitFlow 主工作区编译不过（写进 UNRESOLVED）。"""
import io

SKILL = "/Users/mac/.hermes/skills/colorfuledger/SKILL.md"
UNRES = "/Users/mac/.hermes/UNRESOLVED.md"

SKILL_ANCHOR = "### ⛔⭐⭐⭐ 怎么把 iOS 16 模拟器弄上本机（2026-11-11 全程实测，踩完了）"

SKILL_ADD = """### ⛔⭐⭐⭐ TabView 里放 `if #available` → **用户点底栏切不动**（2026-11-11 夜间档实测，最隐蔽的一个坑）

**症状**：iOS 15/16 兼容层写成
```swift
TabView(selection: $selectedTab) {
    TodayView()                       // ❌ 错：TodayView.body 里直接写
        .tabItem { ... }              //    if #available(iOS 16) { NavigationStack {…} }
        .tag(0)                       //    } else { NavigationView {…} }
}
```
→ **用户点底栏 tab 切不动**（实测 AX 树：点 Stats 后 Today 仍是 Selected）。

**根因**：版本分流（`if #available`）在 **tab 内容里**时，两个分支**类型不同**
→ SwiftUI 认为 tab 内容身份变了 → **重建 tab** → selection 绑定失效。

**⚠️ 这个 bug 编译不报错、单测全绿、商店截图正常** —— 只有 UI 测试能抓到。
截图全绿、用户投诉「点不动」时，先查这里。

**修法**：分流必须放在 **TabView 外面**，让 TabView 自身保持稳定类型：
```swift
if #available(iOS 16.0, *) {
    rootTabs { TodayViewStack() } stack: { StatsViewStack() } legacy: { SettingsViewStack() }
} else {
    rootTabs { TodayViewLegacy() } legacy: { StatsViewLegacy() } legacy2: { SettingsViewLegacy() }
}
```
⚠️ **也不能**在 TabView 里写 `if #available` 选两套 tab —— 那样 TabView 的**直接子视图**
类型也会变 → 同样会重建。

**2026-11-11 全 App 扫描结果（TabView 后 120 行内出现 `if #available`）**：
私密记账 0 / 时间收纳箱 0 / HabitFlow 0（它正在修自己那处）/ 卡点通勤 0 / DailyMe 0 / 萌宠手册 0
⇒ **目前没污染任何 App**，但其它 App 正在做 iOS 15 适配，**随时可能踩**。
扫描脚本：`~/TimeStash/scripts/scan_tabview_available.py`

""" + SKILL_ANCHOR

UNRES_ANCHOR = "\n## 已解决\n"

UNRES_ADD = """
### [开发] HabitFlow 主工作区编译不过 —— iOS 15 适配重构写到一半（2026-11-11 18:4x 夜间档留下）

- **症状**：`xcodebuild` 报 6 个符号找不到：
  `rootTabs` / `TodayViewStack` / `SettingsViewStack` / `TodayViewLegacy` / `SettingsViewLegacy`
  （`ios/HabitFlow/ui/RootView.swift:72-85`）
- **根因**：18:4x 夜间档在做 **iOS 15 兼容层重构**，把 TabView 的版本分流移到 TabView 外面
  （见 skill 里「TabView 里放 if #available → 底栏切不动」那条），
  **但配套的辅助类型还没写**，改动也没提交。
  ⇒ 全工程扫描确认：这 5 个类型**一处定义都没有**（不是「文件没进 target」）。
- **影响**：HabitFlow 主工作区**跑不了任何测试**（编译阶段就挂）；
  夜间开发档会全部失败。
- **⚠️ 这个重构本身是有价值的**，别回退：
  它修的是一个「编译不报错、单测全绿、商店截图正常、但用户点底栏切不动」的隐蔽 bug。
- **处置（二选一，都不能丢改动）**：
  ① **补齐** `rootTabs` / `*ViewStack` / `*ViewLegacy` 这 7 个辅助类型，把重构做完（推荐）；
  ② 先 `git stash` 备份，把 `RootView.swift` 回退到已提交版本，恢复编译，
     之后另起一档重做（别直接 `git checkout` 覆盖，先备份）。
- **注意**：另有会话正在 `/tmp/DataMe_dev/hf_test` worktree 里处理 HabitFlow 的守卫测试，
  **主工作区与它无关，别打架**。

"""


def main():
    # skill
    s = io.open(SKILL, encoding="utf-8").read()
    if "TabView 里放 `if #available`" not in s:
        if SKILL_ANCHOR in s:
            s = s.replace(SKILL_ANCHOR, SKILL_ADD, 1)
            io.open(SKILL, "w", encoding="utf-8").write(s)
            print("OK: skill 已写入 TabView 坑")
        else:
            print("FAIL: skill 锚点没找到")
    else:
        print("skill: 已存在")

    # UNRESOLVED
    u = io.open(UNRES, encoding="utf-8").read()
    if "HabitFlow 主工作区编译不过" not in u:
        if UNRES_ANCHOR in u:
            u = u.replace(UNRES_ANCHOR, UNRES_ADD + UNRES_ANCHOR, 1)
            io.open(UNRES, "w", encoding="utf-8").write(u)
            print("OK: UNRESOLVED 已写入 HabitFlow 条目")
        else:
            print("FAIL: UNRESOLVED 锚点没找到")
    else:
        print("UNRESOLVED: 已存在")


if __name__ == "__main__":
    main()
