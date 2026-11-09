#!/usr/bin/env python3
"""查私密记账各 build 的崩溃诊断签名（ASC performance diagnostics）。

用法：python3 scripts/freeledger_crash_signatures.py [build号...]
不带参数 = 查全部 build。
"""
import json
import os
import subprocess
import sys

APP_ID = "6759187331"


def sh(args, timeout=180):
    env = dict(os.environ)
    env["PATH"] = "/Users/mac/.blitz/bin:" + env.get("PATH", "")
    env["ASC_TIMEOUT"] = "150s"
    try:
        return subprocess.run(args, capture_output=True, text=True, env=env,
                              timeout=timeout).stdout
    except subprocess.TimeoutExpired:
        return ""


def main():
    builds = json.loads(sh(["asc", "builds", "list", "--app", APP_ID, "--output", "json"]))
    items = builds.get("data", [])
    want = set(sys.argv[1:])
    for it in items:
        a = it.get("attributes", {})
        v = a.get("version")
        if want and v not in want:
            continue
        bid = it["id"]
        out = sh(["asc", "performance", "diagnostics", "list", "--build", bid, "--output", "json"])
        try:
            j = json.loads(out) if out.strip() else {}
        except Exception:
            j = {}
        sigs = j.get("data", []) if isinstance(j, dict) else []
        if not sigs:
            # 可能是报错信息
            err = ""
            if isinstance(j, dict) and j.get("errors"):
                err = str(j["errors"])[:120]
            print("build %-4s | 无诊断签名 %s" % (v, err))
            continue
        print("build %-4s | %d 条诊断签名" % (v, len(sigs)))
        for s in sigs:
            at = s.get("attributes", {})
            print("   ", at.get("diagnosticType"), "|", at.get("signature"),
                  "| 版本:", at.get("appVersion"), "| 设备:", at.get("deviceModel"),
                  "| 系统:", at.get("osVersion"), "| 发生:", at.get("firstSeen"),
                  "| 次数:", at.get("occurrences"))
            print("      id:", s.get("id"))


if __name__ == "__main__":
    main()
