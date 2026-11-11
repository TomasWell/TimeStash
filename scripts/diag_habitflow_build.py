import os
import re
import subprocess

C = "/Users/mac/HabitFlow/ios"
SYMS = ["rootTabs", "TodayViewStack", "SettingsViewStack", "TodayViewLegacy", "SettingsViewLegacy"]

# 找每个符号定义在哪
for s in SYMS:
    found = []
    for dirpath, dirnames, filenames in os.walk(C):
        dirnames[:] = [d for d in dirnames
                       if d not in ("DerivedData", "build", ".build", "SourcePackages", ".git")]
        for fn in filenames:
            if not fn.endswith(".swift"):
                continue
            p = os.path.join(dirpath, fn)
            try:
                t = open(p, encoding="utf-8").read()
            except Exception:
                continue
            if re.search(r"\b(struct|class|enum|let|var|func)\s+" + re.escape(s) + r"\b", t):
                found.append(os.path.relpath(p, C))
    print("%-20s 定义在: %s" % (s, found or "★ 找不到定义"))

print()
print("=== 这些文件是否在 Xcode target 里（看 project.pbxproj）===")
pb = os.path.join(C, "HabitFlow.xcodeproj/project.pbxproj")
text = open(pb, encoding="utf-8").read()
for dirpath, dirnames, filenames in os.walk(C):
    dirnames[:] = [d for d in dirnames
                   if d not in ("DerivedData", "build", ".build", "SourcePackages", ".git")]
    for fn in filenames:
        if not fn.endswith(".swift"):
            continue
        p = os.path.join(dirpath, fn)
        rel = os.path.relpath(p, C)
        base = fn[:-6]
        if base not in text:
            print("  ★ 不在 pbxproj 里: %s" % rel)
