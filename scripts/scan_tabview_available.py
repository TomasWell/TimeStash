#!/usr/bin/env python3
"""扫各 App 有没有「TabView 的 tab 内容里放 `if #available`」这个坑。

坑（HabitFlow 2026-11-11 18:4x 夜间档实测）：
    版本分流（`if #available`）写在 **TabView 的 tab 内容里**时，
    两个分支**类型不同** → SwiftUI 认为 tab 内容身份变了 → 重建 tab →
    selection 绑定失效 → **用户点底栏 tab 切不动**。
    ⚠️ 编译不报错、单测全绿、商店截图正常 → 只有 UI 测试能抓到。

判据（按文本结构，宁可多报也不漏报）：
    找到 `TabView` 之后，其花括号范围内是否出现 `if #available`
    （粗略扫整个文件里 TabView 的位置 + 之后 120 行内是否有 `if #available`）
"""
import os
import re

APPS = [
    ("私密记账", "/Users/mac/FreeLedger/ios"),
    ("时间收纳箱", "/Users/mac/TimeStash/ios"),
    ("HabitFlow", "/Users/mac/HabitFlow/ios"),
    ("卡点通勤", "/Users/mac/CommutePilot/ios"),
    ("DailyMe", "/Users/mac/DataMe/ios"),
    ("萌宠手册", "/Users/mac/PawRecord/ios"),
]

SKIP = {"DerivedData", "build", ".build", "SourcePackages", ".git", "Pods"}


def scan(root):
    hits = []
    n = 0
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP]
        for fn in filenames:
            if not fn.endswith(".swift"):
                continue
            p = os.path.join(dirpath, fn)
            rel = os.path.relpath(p, root)
            if "/Tests/" in "/" + rel or "/UITests/" in "/" + rel:
                continue
            n += 1
            try:
                lines = open(p, encoding="utf-8").read().split("\n")
            except Exception:
                continue
            for i, line in enumerate(lines):
                if "TabView" not in line or "struct " in line or "//" in line:
                    continue
                # TabView 之后 120 行内找 if #available
                window = lines[i:i + 120]
                for j, wl in enumerate(window):
                    if "if #available" in wl and not wl.strip().startswith("//"):
                        hits.append("%s:%d  TabView@%d → %s"
                                    % (rel, i + j + 1, i + 1, wl.strip()[:90]))
                        break
    return n, hits


print("%-12s %-8s %-10s %s" % ("App", "扫文件", "命中", "说明"))
print("-" * 60)
for name, root in APPS:
    if not os.path.isdir(root):
        print("%-12s 工程不在 %s" % (name, root))
        continue
    n, hits = scan(root)
    print("%-12s %-8d %-10d" % (name, n, len(hits)))
    for h in hits:
        print("     ⚠️  " + h)
if not any(True for _ in []):
    pass
print()
print("★ 命中 = 疑似「TabView 里放 if #available」；")
print("  还要看它是不是在 **tab 内容位置**（在 TabView 外面/前面 是安全的）。")
