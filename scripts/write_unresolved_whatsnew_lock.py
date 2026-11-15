#!/usr/bin/env python3
"""记录：TimeStash 1.0 版本层的 whatsNew 被 Apple 锁住（首版可留空）。"""
import io

P = "/Users/mac/.hermes/UNRESOLVED.md"
MARKER = "\n## 已解决\n"

ADD = """
### [上架] 时间收纳箱 1.0 的版本层 whatsNew 不可编辑（2026-11-15 实测）

- **报错**：`Attribute 'whatsNew' cannot be edited at this time`
  （`asc localizations update --version 46a2877b-… --locale sk --whats-new "…"`）
- **前提**：该版本 **1.0 处于 PREPARE_FOR_SUBMISSION，从没提交过审核**
  （`asc review history` 为空）⇒ **不是「提交审核后锁定」**。
- **判断**：首版 What's New **允许留空**，Apple 商店页会正常显示版本号与发布说明区。
  `asc review doctor --app 6832234671` 报 **errors 0 / warnings 0 / blocking 0**，
  nextAction = "No submission blockers detected. Submit the version when ready."
  ⇒ **What's New 不是提审必需项**，不影响提交。
- **处置**：跳过 What's New，直接提审。
  后续版本（1.0.1 及以后）再补 What's New —— 那时新建版本槽，字段应当可编辑。
- **⚠️ 另一个待确认点**：1.0 的 whatsNew 锁着，但**版本层其它字段**（描述/关键词）
  是否也锁，需要真提审时才知道；提审前只改不影响商店页的字段。

"""


def main():
    s = io.open(P, encoding="utf-8").read()
    if "时间收纳箱 1.0 的版本层 whatsNew 不可编辑" in s:
        print("已存在，跳过")
        return
    if MARKER not in s:
        print("FAIL: 没找到锚点")
        return
    s = s.replace(MARKER, ADD + MARKER, 1)
    io.open(P, "w", encoding="utf-8").write(s)
    print("OK: 已写入 whatsNew 锁定条目")


if __name__ == "__main__":
    main()
