#!/usr/bin/env python3
"""更新 UNRESOLVED.md 里私密记账线上崩溃那条的进展（2026-11-09）。"""
import io

P = "/Users/mac/.hermes/UNRESOLVED.md"

OLD_TITLE = ("### [上架] 私密记账 1.0.17（build 28）线上「打开就崩」—— "
             "已做兜底修复，根因待真机日志（2026-11-09 13:0x 报障）")
NEW_TITLE = ("### [上架] 私密记账 1.0.17（build 28）线上「打开就崩」—— "
             "兜底已上线(1.0.18审核中)，根因待真机自证（2026-11-09 报障）")

ADDITION = """
- **2026-11-09 14:4x 追加进展**：
  - **1.0.18（build 29）已提交 Apple 审核**（WAITING_FOR_REVIEW，version id
    `018336b9-ae4e-4a84-b957-e05afa00b847`）：含 build 29、48 locale 的 What's New、
    48 locale 各 5 张商店截图（继承自 1.0.17，已用 `asc screenshots list` 逐个核过）。
    ⚠️ 提审时踩的坑：往**空的** reviewSubmission 里 `items-add` 会返回 **500**，
    换一个新 submission 立刻成功（已写进 ios-appstore-release skill）。
  - **Apple 侧拿不到崩溃证据**：`asc performance diagnostics list --build <uuid>`
    对 build 26/27/28/29 **一条签名都没有**（用户多半没开「与 Apple 共享诊断」）；
    `asc analytics` 只有框架使用统计，**没有崩溃明细**。
  - **⇒ 改为在 App 内建自证通道**（1.0.19 / build 30，已提交代码）：
    设置页新增「复制诊断信息」，一键复制版本/系统/机型(hw.machine)/磁盘剩余/
    DB 文件大小/迁移到第几版/**App Group 容器真机是否可用**/恢复状态与失败原因。
    **只含元信息，绝不含金额商家备注账户名**（有测试锁死）。
    用户点一下粘给我们即可定位根因 —— 比让用户去翻「分析数据」可靠。
  - **兜底再硬化**：新库自身迁移失败原来被 `try?` 吞掉，会留下「能打开但没表」的半残库，
    后续每个查询抛 "no such table"，表现成莫名其妙的崩溃。现由
    `DatabaseRecoveryState.freshDatabaseFailed` 单独标记，界面提示「存储空间不足」。
  - **1.0.19 / build 30 的去处**：先发 **TestFlight 内部测试组**（组内已有用户
    tomaswell163@gmail.com，状态 INVITED；内部测试**不过 Beta 审核**），
    让用户立刻能装上验证。**正式版等 1.0.18 过审后再提 1.0.19**（同一 App 一次只能有一个版本在审）。
  - **仍需用户一步**（若仍崩）：装上后「设置 → 复制诊断信息」→ 粘给我。

"""


def main():
    with io.open(P, encoding="utf-8") as f:
        s = f.read()

    changed = []
    if OLD_TITLE in s:
        s = s.replace(OLD_TITLE, NEW_TITLE)
        changed.append("标题")

    marker = "\n## 已解决\n"
    if marker in s and "2026-11-09 14:4x 追加进展" not in s:
        s = s.replace(marker, ADDITION + marker, 1)
        changed.append("进展")
    elif "2026-11-09 14:4x 追加进展" in s:
        print("（进展已存在，跳过）")

    with io.open(P, "w", encoding="utf-8") as f:
        f.write(s)
    print("已更新:", changed or "无变化")


if __name__ == "__main__":
    main()
