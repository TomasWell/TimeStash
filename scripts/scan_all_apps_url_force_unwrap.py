#!/usr/bin/env python3
"""扫所有 App 的**产品代码**，找 iOS 16 会崩的 `URL(string:)!` 强制解包。

起因：私密记账 1.0.18 在 iOS 16.1 上「打开即崩」，根因就是
`URL(string: "mailto:...?subject=\\(L("app_name"))%20Feedback")!`
—— iOS 16 及更早的 Foundation 按旧 RFC 1738/1808 解析，遇到非 ASCII 返回 nil → 强解包 → Swift trap。

哪些 App 会中招：deploymentTarget ≤ 16 的（iOS 16 用户能装 = 有真实用户受影响）。
"""
import os
import re
import subprocess

P1 = re.compile(r"URL\s*\(\s*string:[^)]*\)\s*!")
P2 = re.compile(r'URL\s*\(\s*string:[^)]*L\(\s*"')

APPS = [
    ("私密记账", "/Users/mac/FreeLedger/ios"),
    ("时间收纳箱", "/Users/mac/TimeStash/ios"),
    ("HabitFlow", "/Users/mac/HabitFlow/ios"),
    ("卡点通勤", "/Users/mac/CommutePilot/ios"),
    ("DailyMe", "/Users/mac/DataMe/ios"),
    ("萌宠手册", "/Users/mac/PawRecord/ios"),
]

SKIP_DIRS = {"DerivedData", ".build", "SourcePackages", "build", "Pods", ".git"}


def deployment_target(root):
    for fn in ("project.yml",):
        p = os.path.join(root, fn)
        if not os.path.exists(p):
            continue
        t = open(p, encoding="utf-8").read()
        m = re.search(r'deploymentTarget:\s*\n\s*iOS:\s*"([^"]+)"', t)
        if m:
            return m.group(1)
    return "?"


def scan(root):
    hits1, hits2 = [], []
    n = 0
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for fn in filenames:
            if not fn.endswith(".swift"):
                continue
            p = os.path.join(dirpath, fn)
            # 排除测试目录（守卫要守的是产品代码）
            rel = os.path.relpath(p, root)
            if "/Tests/" in "/" + rel or "/UITests/" in "/" + rel or rel.endswith("Tests.swift"):
                continue
            n += 1
            try:
                text = open(p, encoding="utf-8").read()
            except Exception:
                continue
            for i, line in enumerate(text.split("\n"), 1):
                t = line.strip()
                if t.startswith("//") or t.startswith("///") or t.startswith("*"):
                    continue
                if P1.search(line):
                    hits1.append("%s:%d  %s" % (rel, i, t[:110]))
                elif P2.search(line):
                    hits2.append("%s:%d  %s" % (rel, i, t[:110]))
    return n, hits1, hits2


print("%-12s %-8s %-6s %-8s %-8s" % ("App", "minOS", "扫文件", "强解包", "本地化拼URL"))
print("-" * 56)
total = 0
for name, root in APPS:
    if not os.path.isdir(root):
        print("%-12s %s" % (name, "（工程不在 %s）" % root))
        continue
    dt = deployment_target(root)
    n, h1, h2 = scan(root)
    total += len(h1)
    print("%-12s %-8s %-6d %-8d %-8d" % (name, dt, n, len(h1), len(h2)))
    for h in h1:
        print("     ⛔ " + h)
    for h in h2:
        print("     ⚠️  " + h)
print()
print("产品代码里的 `URL(string:)!` 合计: %d 处" % total)
print("（minOS ≤ 16 的 App 才会让 iOS 16 用户崩；私密记账已修）")
