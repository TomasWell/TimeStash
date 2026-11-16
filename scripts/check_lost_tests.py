#!/usr/bin/env python3
"""找出「启动了但从未报结果」的 XCTest 用例 —— 即**静默丢失**的用例。

⚠️ 为什么需要（2026-11-16 22:48 夜间档实测）：
   UI 测试 runner 进程自己死掉时，xcodebuild 会自动重启 runner 并**从下一个用例接着跑**，
   死在半路的那一个用例**既没 passed 也没 failed** —— 断言根本没跑完，也没人知道。

   实测数字：89 个用例 started，只有 88 个报 passed；
   `BudgetGoalLiabUITests.test02_GoalsFullChain` 从头到尾没出现在 passed 里。

⚠️ 为什么旧的三道校验发现不了：
   - 「用例数 > 0」→ 照样 > 0（丢失的用例已经被计入）
   - 「0 failures」→ 照样是 0（没报 failed）
   - 「0 崩溃」→ 照样是 0（死的是 **runner**，不是 App，没有 .ips 崩溃报告）
   ⇒ 三道全绿，但**有一个用例的断言根本没跑完**。这就是本脚本要堵的洞。

用法：
    python3 scripts/check_lost_tests.py /tmp/ColorFuLedger_test.log
    → 退出码 0 = 没丢；退出码 1 = 有用例静默丢失
"""
from __future__ import annotations

import re
import sys

# ⚠️ 正则必须写成 `([^\]]+)` 抓「类名 + 用例名」两段。
#   写成 `.*` 会**贪婪吞掉类名**，导致后面的空格永远匹配不上 → 一个用例都抓不到
#   → 脚本永远说「没丢」→ **假绿**（本脚本第一版就踩了这个坑，实测抓不到
#   日志里明明丢了的那一个用例）。
CASE = re.compile(r"Test Case '-\[(\S+) ([^\]]+)\]' (started|passed|failed)")


def find_lost(log_path: str) -> list[str]:
    started: set[str] = set()
    finished: set[str] = set()
    with open(log_path, errors="ignore") as fh:
        for line in fh:
            m = CASE.search(line)
            if not m:
                continue
            key = f"{m.group(1)}.{m.group(2)}"
            if m.group(3) == "started":
                started.add(key)
            else:
                finished.add(key)
    return sorted(started - finished)


def main() -> int:
    if len(sys.argv) < 2:
        print("用法：python3 check_lost_tests.py <xcodebuild 日志>", file=sys.stderr)
        return 2
    try:
        lost = find_lost(sys.argv[1])
    except OSError as exc:
        print(f"读不到日志 {sys.argv[1]}：{exc}", file=sys.stderr)
        return 2
    if not lost:
        print("✅ 没有「启动了但没报结果」的用例")
        return 0
    print(f"⛔ 有 {len(lost)} 个用例**启动了但从未报结果**（runner 中途死掉，这批断言没跑完）：")
    for name in lost[:20]:
        print(f"   - {name}")
    if len(lost) > 20:
        print(f"   ...（另有 {len(lost) - 20} 个）")
    return 1


if __name__ == "__main__":
    sys.exit(main())
