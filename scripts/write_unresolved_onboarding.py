#!/usr/bin/env python3
"""记录私密记账引导页的底部遮挡缺陷到 UNRESOLVED.md（2026-11-11）。"""
import io

P = "/Users/mac/.hermes/UNRESOLVED.md"

MARKER = "\n## 已解决\n"

ADDITION = """
### [UI] 私密记账引导页「选择语言」最后一项被底部控件遮住（2026-11-11 用 iOS 16.4 模拟器发现）

- **现象**：引导页第 1 步「Select Language / 选择语言」的语言列表是滚动列表，
  但底部固定着**分页指示器 + Next 按钮 + Skip 按钮**，
  **列表最后一项（Português (Brazil)）被压住，副标题完全看不见**。
  截图存档：`~/TimeStash/docs/ios16-crash-evidence/ios16.4-build31-launch.png`
  和 `ios17.4-build31-launch.png`。
- **⚠️ 不是 iOS 16 特有的**：iOS 17.4 上**完全一样** ⇒ 是**既有的引导页布局缺陷**，
  所有系统版本、46 个语言列表都这样（只是滚动到底能看见）。
- **影响**：引导页是商店页评分的第一印象；「跳过」按钮也压在列表内容上。
- **为什么现在不修**：1.0.20（build 31）正在 Apple 审核中，改代码就得重出包重提审，
  代价远大于收益，且与 P0（iOS 16 打开即崩）无关。
- **修法（1.0.21 做）**：给滚动列表加**底部内边距**（`.safeAreaPadding(.bottom, X)` 或
  `contentMargins`），高度至少覆盖「分页指示器 + Next + Skip」的总高；
  或者把底部控件改成叠在列表之上并给列表加 `.safeAreaInset(edge: .bottom)`。
- **待办**：1.0.20 过审上架后再修；**同一批要检查另外几个 App 的引导页**
  （时间收纳箱 4 页引导页、HabitFlow、卡点通勤、DailyMe、萌宠手册）。

"""


def main():
    with io.open(P, encoding="utf-8") as f:
        s = f.read()
    if "引导页「选择语言」最后一项被底部控件遮住" in s:
        print("已存在，跳过")
        return
    if MARKER not in s:
        print("FAIL: 没找到「## 已解决」标记")
        return
    s = s.replace(MARKER, ADDITION + MARKER, 1)
    with io.open(P, "w", encoding="utf-8") as f:
        f.write(s)
    print("OK: 已写入引导页底部遮挡条目")


if __name__ == "__main__":
    main()
