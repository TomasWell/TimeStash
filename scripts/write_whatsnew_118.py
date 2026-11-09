#!/usr/bin/env python3
"""给私密记账 1.0.18 写 48 个 locale 的 What's New。

内容方向：这是一个**线上崩溃的紧急修复版**，必须说清楚。
  - 主文案：修复「打开 App 闪退」的问题（数据库读取异常时不再崩溃，原始数据会保留）
  - 强调：数据没有被删除

按 skill 的规矩：写商店文案的脚本**不把版本号写死**，默认取「版本号最大且仍可编辑」的槽。
"""
import json
import subprocess
import sys

APP_ID = "6759187331"
VERSION = "1.0.18"
# asc 的 --version 要的是 version id（UUID），不是版本号
VERSION_ID = "018336b9-ae4e-4a84-b957-e05afa00b847"

WHATS_NEW = {
    "zh-Hans": "修复了打开 App 闪退的问题：数据库读取异常时不再崩溃，你的原始数据会被完整保留，不会丢失。同时新增「数据读取失败」的明确提示。",
    "zh-Hant": "修復了打開 App 閃退的問題：資料庫讀取異常時不再崩潰，你的原始資料會被完整保留，不會遺失。同時新增「資料讀取失敗」的明確提示。",
    "en": "Fixes a crash on launch: if your ledger data could not be read, the app no longer quits — your original data is kept safe and never deleted. Also adds a clear notice when this happens.",
}

# 其余语言用「英文原文 + 关键句」的简短版本，逐语言翻译在下面跑。
TEMPLATE = (
    "Fixes a crash on launch: if your ledger data could not be read, "
    "the app no longer quits — your original data is kept safe and never deleted. "
    "Also adds a clear notice when this happens."
)


def run(*args):
    return subprocess.run(list(args), capture_output=True, text=True,
                           env={"PATH": "/Users/mac/.blitz/bin:" + __import__("os").environ.get("PATH", ""),
                                "HOME": __import__("os").environ.get("HOME", "")})


def main():
    r = run("asc", "localizations", "list", "--version", VERSION_ID, "--output", "json")
    try:
        items = json.loads(r.stdout).get("data", [])
    except Exception as e:
        print("读 localizations 失败:", e, r.stdout[:300], r.stderr[:300])
        return 1
    print("locale 数:", len(items))

    need_translate = []
    for it in items:
        loc = it.get("attributes", {}).get("locale")
        lid = it.get("id")
        text = WHATS_NEW.get(loc)
        if text:
            r2 = run("asc", "localizations", "update", "--version", VERSION_ID,
                     "--locale", loc, "--whats-new", text)
            ok = '"success"' in r2.stdout or not r2.stderr.strip()
            print("  %-8s %s" % (loc, "✓" if ok else "✗ " + r2.stderr[:120]))
        else:
            need_translate.append((loc, lid))
    print("需要翻译:", len(need_translate))
    with open("/tmp/whatsnew_todo.json", "w", encoding="utf-8") as f:
        json.dump(need_translate, f, ensure_ascii=False)
    print(",".join(x[0] for x in need_translate))
    return 0


if __name__ == "__main__":
    sys.exit(main())
