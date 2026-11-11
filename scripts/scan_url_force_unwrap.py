#!/usr/bin/env python3
"""按 TimeStashTests/URLConstructionGuardTests 的同一套规则，扫出 offender。

规则（来自守卫测试源码）：
  ① `URL(string: ...)!` 强制解包
  ② 本地化文案 L("...") 直接拼进 URL(string:)
根目录 = ios/（守卫测试文件在 ios/<App>Tests/ 下，往上两级）
"""
import os
import re

ROOT = "/Users/mac/TimeStash/ios"
P1 = re.compile(r"URL\s*\(\s*string:[^)]*\)\s*!")
P2 = re.compile(r'URL\s*\(\s*string:[^)]*L\(\s*"')

found1 = []
found2 = []
n = 0
for dirpath, dirnames, filenames in os.walk(ROOT):
    dirnames[:] = [d for d in dirnames
                   if d not in ("DerivedData", ".build", "SourcePackages", "build")]
    for fn in filenames:
        if not fn.endswith(".swift"):
            continue
        p = os.path.join(dirpath, fn)
        n += 1
        try:
            text = open(p, encoding="utf-8").read()
        except Exception:
            continue
        for i, line in enumerate(text.split("\n"), 1):
            t = line.strip()
            if t.startswith("//") or t.startswith("///") or t.startswith("*"):
                continue
            rel = os.path.relpath(p, ROOT)
            if P1.search(line):
                found1.append("%s:%d  %s" % (rel, i, t))
            elif P2.search(line):
                found2.append("%s:%d  %s" % (rel, i, t))

print("扫了 %d 个 .swift 文件" % n)
print()
print("=== ① URL(string: ...)! 强制解包 ===")
for f in found1:
    print("  ", f)
print("   共 %d 处" % len(found1))
print()
print("=== ② 本地化文案直接拼进 URL(string:) ===")
for f in found2:
    print("  ", f)
print("   共 %d 处" % len(found2))
