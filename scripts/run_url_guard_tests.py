#!/usr/bin/env python3
"""实跑各 App 的 URLConstructionGuardTests，确认它们到底红不红。

背景（2026-11-11）：
- 5 个 App 各有一份 URL 构造守卫（memory #290）
- TimeStash 那份是 76 行的简易版，**会把自己的断言消息扫进去** → 误报（已修）
- HabitFlow / 卡点通勤 / DailyMe / 萌宠手册 用的是同一份 349 行严谨版
  （带词法扫描 strippingComments + appSourceDirectoryName 限定只扫产品代码目录）
  —— 推测**不会**自匹配，但**必须实跑验证**，不能靠猜

用法：python3 run_url_guard_tests.py
"""
import os
import subprocess
import sys
import time

APPS = [
    ("HabitFlow", "/Users/mac/HabitFlow/ios", "HabitFlow", "HabitFlowTests"),
    ("卡点通勤", "/Users/mac/CommutePilot/ios", "CommutePilot", "CommutePilotTests"),
    ("DailyMe", "/Users/mac/DataMe/ios", "DataMe", "DataMeTests"),
    ("萌宠手册", "/Users/mac/PawRecord/ios", "PawRecord", "PawRecordTests"),
    ("时间收纳箱", "/Users/mac/TimeStash/ios", "TimeStash", "TimeStashTests"),
]

# 用 iOS 16.4 那台，避开夜间档常用的 iPhone 15 Pro
SIM = "E4D10850-FEEF-44F0-A251-70AD5841D0BE"


def sh(cmd, timeout=120):
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    return r.stdout, r.stderr, r.returncode


def main():
    results = {}
    for name, ios_dir, scheme, test_target in APPS:
        proj = os.path.join(ios_dir, scheme + ".xcodeproj")
        if not os.path.exists(proj):
            print("%-12s 工程不存在: %s" % (name, proj))
            continue
        dd = "/tmp/guard-%s" % scheme
        cmd = ["xcodebuild", "test",
               "-project", proj, "-scheme", scheme,
               "-destination", "platform=iOS Simulator,id=" + SIM,
               "-derivedDataPath", dd,
               "-only-testing:%s/URLConstructionGuardTests" % test_target]
        print("=== %s ===" % name, flush=True)
        out, err, rc = sh(cmd, timeout=1500)
        text = out + err
        # Swift Testing 的输出看 "Test run with N tests"
        m = [l.strip() for l in text.split("\n") if "Test run with" in l]
        fails = [l.strip() for l in text.split("\n") if "recorded an issue" in l]
        print("   ", (m[-1] if m else "（没抓到 Test run 行）")[:150])
        if fails:
            print("    ❌ 失败:")
            for f in fails[:4]:
                print("      ", f[:160])
        else:
            print("    ✅ 无失败")
        results[name] = not fails
        print()

    print("===== 汇总 =====")
    for k, v in results.items():
        print("  %-12s %s" % (k, "✅ 通过" if v else "❌ 有失败"))
    return 0 if all(results.values()) else 1


if __name__ == "__main__":
    sys.exit(main())
