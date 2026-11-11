#!/usr/bin/env python3
"""检查各 App 的 URLConstructionGuardTests 是否有「扫到自己」的 bug，并修掉。

bug：守卫的断言消息里写着字面量 `URL(string: ...)!`，
被自己的正则 `URL\\s*\\(\\s*string:[^)]*\\)\\s*!` 匹配上 → 每次跑都误报。

修法：扫描时排除 Tests / UITests 目录（守卫的对象是产品代码）。

（2026-11-11：TimeStash 的那份已修；这个脚本把其余几个 App 的一并修好，
否则它们的夜间档跑测试会被自己卡红。）
"""
import os
import re
import subprocess
import sys

APPS = [
    ("私密记账", "/Users/mac/FreeLedger/ios"),
    ("时间收纳箱", "/Users/mac/TimeStash/ios"),
    ("HabitFlow", "/Users/mac/HabitFlow/ios"),
    ("卡点通勤", "/Users/mac/CommutePilot/ios"),
    ("DailyMe", "/Users/mac/DataMe/ios"),
    ("萌宠手册", "/Users/mac/PawRecord/ios"),
]

FIX = """            if p.contains("/Tests/") || p.contains("/UITests/") || p.hasSuffix("Tests.swift") { continue }
"""

COMMENT = ("            // ⛔ 排除测试目录：守卫的断言消息里含字面量 `URL(string: ...)!`，\n"
           "            //    会被自己的正则匹配上 → 每次都误报（守卫要守的是产品代码）。\n")


def main():
    apply_fix = "--fix" in sys.argv
    for name, root in APPS:
        if not os.path.isdir(root):
            print("%-12s 工程不在 %s" % (name, root))
            continue
        # 找守卫文件
        cands = []
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = [d for d in dirnames
                           if d not in ("DerivedData", ".build", "SourcePackages", "build", ".git")]
            for fn in filenames:
                if fn == "URLConstructionGuardTests.swift":
                    cands.append(os.path.join(dirpath, fn))
        if not cands:
            print("%-12s 没有 URLConstructionGuardTests.swift" % name)
            continue
        for p in cands:
            rel = os.path.relpath(p, root)
            text = open(p, encoding="utf-8").read()
            if '/Tests/' in text or '/UITests/' in text:
                print("%-12s %s → 已排除测试目录 ✅" % (name, rel))
                continue
            if apply_fix:
                # 在 SourcePackages 那行之后插入排除
                anchor = 'if p.contains("/SourcePackages/") { continue }\n'
                if anchor in text:
                    text = text.replace(anchor, anchor + COMMENT + FIX, 1)
                    open(p, "w", encoding="utf-8").write(text)
                    print("%-12s %s → 已修 ✅" % (name, rel))
                else:
                    print("%-12s %s → 找不到锚点，需手工处理 ⚠️" % (name, rel))
            else:
                print("%-12s %s → 会自匹配误报 ⚠️（加 --fix 修）" % (name, rel))


if __name__ == "__main__":
    main()
