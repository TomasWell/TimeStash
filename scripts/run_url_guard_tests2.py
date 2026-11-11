#!/usr/bin/env python3
"""实跑各 App 的 URLConstructionGuardTests，**必须有用例数 > 0 才算通过**。

⚠️ 2026-11-11 踩过的坑：
- `-only-testing:<Target>/<Class>` 对 XCTest 有效，但**偶尔匹配不到** → 输出
  `Executed 0 tests` + `** TEST SUCCEEDED **` = **假成功**
- 所以判据不能是「没看到失败行」，必须是「**看到了 N>0 个用例执行**」
- Swift Testing 的用例数看 `✔ Test run with N tests in M suites passed`；
  XCTest 的看 `Executed N tests, with 0 failures`（N 要 > 0）

用法：python3 run_url_guard_tests2.py
"""
import os
import re
import subprocess
import sys

APPS = [
    ("HabitFlow", "/Users/mac/HabitFlow/ios", "HabitFlow", "HabitFlowTests"),
    ("卡点通勤", "/Users/mac/CommutePilot/ios", "CommutePilot", "CommutePilotTests"),
    ("DailyMe", "/Users/mac/DataMe/ios", "DataMe", "DataMeTests"),
    ("萌宠手册", "/Users/mac/PawRecord/ios", "PawRecord", "PawRecordTests"),
    ("时间收纳箱", "/Users/mac/TimeStash/ios", "TimeStash", "TimeStashTests"),
]

SIM = "E4D10850-FEEF-44F0-A251-70AD5841D0BE"

RE_RUN = re.compile(r"Test run with (\d+) tests? in (\d+) suites?")
RE_EXEC = re.compile(r"Executed (\d+) tests?, with (\d+) failures?")


def main():
    rows = []
    for name, ios_dir, scheme, target in APPS:
        proj = os.path.join(ios_dir, scheme + ".xcodeproj")
        if not os.path.exists(proj):
            print("%-12s 工程不存在" % name, flush=True)
            rows.append((name, "跳过", 0, 0, ""))
            continue
        cmd = ["xcodebuild", "test", "-project", proj, "-scheme", scheme,
               "-destination", "platform=iOS Simulator,id=" + SIM,
               "-derivedDataPath", "/tmp/guard2-" + scheme,
               "-only-testing:%s/URLConstructionGuardTests" % target]
        print("=== %s ===" % name, flush=True)
        try:
            p = subprocess.run(cmd, capture_output=True, text=True, timeout=1800)
            text = p.stdout + p.stderr
        except subprocess.TimeoutExpired:
            print("    超时")
            rows.append((name, "超时", 0, 0, ""))
            continue

        ran = 0
        suites = 0
        m = RE_RUN.findall(text)
        if m:
            ran, suites = int(m[-1][0]), int(m[-1][1])
        else:
            e = RE_EXEC.findall(text)
            if e:
                ran, fails = int(e[-1][0]), int(e[-1][1])
        fails = [l.strip() for l in text.split("\n")
                 if "recorded an issue" in l or "XCTAssertTrue failed" in l
                 or "XCTAssertEqual failed" in l]
        err = [l.strip() for l in text.split("\n") if l.strip().startswith("error:")]

        verdict = "✅ 通过" if (ran > 0 and not fails) else ("❌ 失败" if fails else "⚠️ 未验证")
        print("    执行用例: %d（suites %d）| 失败行: %d | %s" % (ran, suites, len(fails), verdict))
        for f in fails[:3]:
            print("       ", f[:170])
        for e in err[:2]:
            print("      error:", e[:170])
        if ran == 0:
            print("      ⚠️ 用例数 = 0 → 过滤器没匹配上，不能算通过")
        rows.append((name, verdict, ran, suites, fails[0][:120] if fails else ""))

    print()
    print("===== 汇总（判据：用例数 > 0 且无失败）=====")
    bad = 0
    for name, verdict, ran, suites, detail in rows:
        print("  %-12s %-10s 用例 %d" % (name, verdict, ran))
        if verdict != "✅ 通过":
            bad += 1
    return 0 if bad == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
