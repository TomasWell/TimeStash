#!/usr/bin/env python3
"""`check_lost_tests.py` 的自测 —— **守卫自己的守卫**。

为什么必须测（2026-11-16 22:48 夜间档实测）：
判据逻辑第一版把正则写成 `Test Case '-\[.*\] (.*?)' started` ——
`**`贪婪**吞掉了类名**，后面那个空格永远匹配不上 → **一个用例都抓不到**
→ 脚本永远输出「没有丢失」= **假绿**。
⇒ 「守卫能不能抓到东西」必须用**构造样本**证明，不能靠「跑一次没报错」。

跑法：python3 scripts/test_check_lost_tests.py
"""
from __future__ import annotations

import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from check_lost_tests import find_lost  # noqa: E402

PASS = 0
FAIL = 0


def check(name: str, cond: bool, detail: str = "") -> None:
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f"  ✅ {name}")
    else:
        FAIL += 1
        print(f"  ❌ {name}  {detail}")


def write(log: str) -> str:
    fh = tempfile.NamedTemporaryFile("w", suffix=".log", delete=False)
    fh.write(log)
    fh.close()
    return fh.name


print("① 正常日志：全部用例都报了结果 → 无丢失")
path = write(
    "Test Case '-[ColorFuLedgerUITests.SuiteA test01_X]' started.\n"
    "Test Case '-[ColorFuLedgerUITests.SuiteA test01_X]' passed (1.0 seconds).\n"
    "Test Case '-[ColorFuLedgerUITests.SuiteB test02_Y]' started.\n"
    "Test Case '-[ColorFuLedgerUITests.SuiteB test02_Y]' failed (0.5 seconds).\n"
)
check("failed 也算「有结果」", find_lost(path) == [], f"实际 {find_lost(path)}")

print("② runner 中途死掉：started 但没有 passed/failed → 必须抓出来")
path = write(
    "Test Case '-[ColorFuLedgerUITests.SuiteA test01_X]' started.\n"
    "Test Case '-[ColorFuLedgerUITests.SuiteA test01_X]' passed (1.0 seconds).\n"
    "Test Case '-[ColorFuLedgerUITests.SuiteB test02_Y]' started.\n"
    "Restarting after unexpected exit, crash, or test timeout; summary will include totals from previous launches.\n"
    "Test Case '-[ColorFuLedgerUITests.SuiteC test03_Z]' started.\n"
    "Test Case '-[ColorFuLedgerUITests.SuiteC test03_Z]' passed (2.0 seconds).\n"
)
lost = find_lost(path)
check("抓到丢失的用例", len(lost) == 1, f"实际 {lost}")
check("抓到的是对的那个", lost and lost[0].endswith("SuiteB.test02_Y"), f"实际 {lost}")

print("③ **反向验证**：把正则写错（`.*` 贪婪版）必须抓不到 → 说明判据本身有雷")
import re  # noqa: E402
BAD = re.compile(r"Test Case '-\[.*\] (.*?)' started")
GOOD = re.compile(r"Test Case '-\[(\S+) ([^\]]+)\]' (started|passed|failed)")
sample = "Test Case '-[ColorFuLedgerUITests.SuiteB test02_Y]' started.\n"
check("贪婪版正则抓不到（这就是第一版的 bug）", BAD.search(sample) is None)
check("修正版正则能抓到", GOOD.search(sample) is not None,
      f"实际 {GOOD.search(sample)}")

print("④ 空日志 / 只有别的内容 → 不报错、不误报")
path = write("some unrelated output\n")
try:
    check("空日志不炸", find_lost(path) == [])
except Exception as exc:  # noqa: BLE001
    check("空日志不炸", False, f"抛异常 {exc}")

print(f"\n{'✅ 全部通过' if FAIL == 0 else f'❌ {FAIL} 个失败'}（{PASS} 项通过）")
sys.exit(1 if FAIL else 0)
