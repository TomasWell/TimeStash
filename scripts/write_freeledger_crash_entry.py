#!/usr/bin/env python3
"""把「私密记账线上崩溃」的排查结论写进 UNRESOLVED.md 的「未解决」区。

2026-11-09 用户报障：私密记账线上版本（1.0.17 / build 28）打开就崩。
本脚本记录已排查到的范围与仍需用户配合的一步。
"""
import io
import os

PATH = os.path.expanduser('~/.hermes/UNRESOLVED.md')

ENTRY = '''### [上架] 私密记账 1.0.17（build 28）线上「打开就崩」—— 已做兜底修复，根因待真机日志（2026-11-09 13:0x 报障）

- **现象**：用户报「私密记账的线上版本打开就崩溃」。线上版 = **1.0.17 / build 28**（11-06 上传，
  iTunes lookup 与 ASC 双向确认）。这是唯一在售版本。
- **已排除的（模拟器四场景全都不崩）**：
  1. 全新安装 → 正常
  2. 自造 v17 老库（残缺 schema）+ 数据 → 迁移 v18~v21 正常
  3. **真实 build 27（1.0.16）自己建的老库 + 真实数据 → 覆盖升级 build 28 → 正常**
  4. 跳过引导真正进到 ContentView（首页数据正确）→ 正常
  → 说明**不是 build 28 的代码在模拟器上必崩**，也不是升级迁移路径必崩。
- **已查过的可疑点，均排除**：
  - 迁移 v18~v21（build 27→28 新增的 4 个）：都做了「表在不在」的防护，实测能跑
  - v18 反推期初余额的 SQL 口径：与 `AccountDAO.netAmounts` 一致
  - `LanguageManager` 语言回退：已正确退到 en.lproj，不是 `.main`
  - entitlements 变化（新增 App Group）：不影响启动；App Group 访问点全是 `if let`/`guard let`
  - 描述文件：App Group + iCloud 容器齐全
  - iCloud/CloudKit：只在设置页手动触发，不在启动路径
- **已做的修复（兜底，先让用户能打开）**：
  `AppDatabase.init` 原来是 `fatalError("Database initialization failed")` —— **数据库一失败就杀进程**，
  用户点开就是闪退、**打不开自己的账本**。对记账 App 这是最严重的故障形态。
  改成：失败时**老库改名保留（绝不删）** + 新建空库让 App 能开 + 界面明确提示 + 记录原因。
  新增回归测试 `DatabaseRecoveryTests`（3 项：故障注入不崩 / 老库被保留 / 状态被记录）。
  → **即使根因未定位，用户也不会再遇到「点开就闪退」**。
- **卡在哪**：崩溃只出现在**真机**（模拟器四种场景都复现不出来）。要定位根因，
  必须拿到真机崩溃日志 —— iPhone 上路径：
  **设置 → 隐私与安全性 → 分析与改进 → 分析数据 → 找到「私密记账」**（里面有崩溃时间和调用栈）。
  这是**唯一还需用户点一次**的一步，其余（打包、发版）由 agent 完成。
- **待做**：拿日志定位根因 → 出 build 29 → 发版。

'''

MARKER = '## 未解决\n'

with io.open(PATH, encoding='utf-8') as f:
    s = f.read()

if '私密记账 1.0.17（build 28）线上「打开就崩」' in s:
    print('已存在，跳过')
else:
    assert MARKER in s, '未找到「未解决」区标记'
    s = s.replace(MARKER, MARKER + '\n' + ENTRY, 1)
    with io.open(PATH, 'w', encoding='utf-8') as f:
        f.write(s)
    print('已写入 UNRESOLVED.md')
