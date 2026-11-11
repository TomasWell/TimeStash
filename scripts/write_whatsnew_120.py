#!/usr/bin/env python3
"""给私密记账 1.0.20 写 What's New（48 个 locale）。

内容方向：**修复 iOS 16 设备上「打开 App 立刻闪退」**。
这是 1.0.18 上架后用户真机崩溃日志定案的根因，必须说清楚「能打开了」。
中英繁直接写死，其余语言走 MiniMax 直连翻译（不走 hermes chat —— 那条路会静默失败）。
"""
import json
import os
import shutil
import subprocess
import sys

APP_ID = "6759187331"
VERSION_ID = None  # 由调用方传入，或从环境变量读

WHATS_NEW = {
    "zh-Hans": "修复了在 iOS 16 及更早系统上打开 App 立刻闪退的问题：部分手机的系统会对中文链接地址解析失败，之前会导致 App 无法启动。现在已能正常打开，你的账本数据不受影响。同时新增「复制诊断信息」，遇到问题可一键把状态发给我们。",
    "zh-Hant": "修復了在 iOS 16 及更早系統上打開 App 立刻閃退的問題：部分手機的系統會對中文連結地址解析失敗，之前會導致 App 無法啟動。現在已能正常打開，你的帳本資料不受影響。同時新增「複製診斷資訊」，遇到問題可一鍵把狀態發給我們。",
    "en": "Fixes an immediate crash on launch for devices running iOS 16 or earlier: some systems failed to parse a non-ASCII link address, which could prevent the app from starting at all. The app now opens normally and your ledger data is unaffected. You can also copy diagnostic info from Settings if anything goes wrong.",
}

SOURCE = WHATS_NEW["en"]
KEY = "whatsnew_120"
TMP = "/tmp/whatsnew_120_i18n"


def sh(cmd, cwd=None):
    env = dict(os.environ)
    env["PATH"] = "/Users/mac/.blitz/bin:" + env.get("PATH", "")
    return subprocess.run(cmd, capture_output=True, text=True, env=env, cwd=cwd)


def main():
    version_id = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("VERSION_ID")
    if not version_id:
        print("用法: write_whatsnew_120.py <version_id>")
        return 1

    out = sh(["asc", "localizations", "list", "--version", version_id, "--output", "json"]).stdout
    try:
        items = json.loads(out).get("data", [])
    except Exception as e:
        print("读 localizations 失败:", e, out[:300])
        return 1
    print("locale 数:", len(items))

    need = []
    for it in items:
        loc = it.get("attributes", {}).get("locale")
        if loc in WHATS_NEW:
            r = sh(["asc", "localizations", "update", "--version", version_id,
                    "--locale", loc, "--whats-new", WHATS_NEW[loc]])
            ok = r.returncode == 0 and not r.stderr.strip()
            print("  %-8s %s" % (loc, "✓" if ok else "✗ " + r.stderr[:120]))
        else:
            need.append(loc)
    print("需要翻译:", len(need))
    json.dump(need, open("/tmp/whatsnew_120_todo.json", "w", encoding="utf-8"))

    if not need:
        return 0

    # 翻译：用 translate-strings.py（MiniMax 直连），基准 en
    shutil.rmtree(TMP, ignore_errors=True)
    os.makedirs(TMP, exist_ok=True)
    for loc in need:
        d = os.path.join(TMP, f"{loc}.lproj")
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, "Localizable.strings"), "w", encoding="utf-8") as f:
            f.write('"%s" = "%s";\n' % (KEY, SOURCE))
    base = os.path.join(TMP, "en.lproj")
    os.makedirs(base, exist_ok=True)
    with open(os.path.join(base, "Localizable.strings"), "w", encoding="utf-8") as f:
        f.write('"%s" = "%s";\n' % (KEY, SOURCE))

    r = sh(["python3", "translate-strings.py", "--i18n-dir", TMP, "--base", "en",
            "--batch", "2", "--progress-file", "/tmp/whatsnew_120_progress.json"],
           cwd="/Users/mac/FreeLedger/scripts/i18n")
    print(r.stdout[-900:])
    if r.returncode != 0:
        print("翻译有报错:", r.stderr[-400:])

    ok = 0
    fail = []
    for loc in need:
        p = os.path.join(TMP, f"{loc}.lproj", "Localizable.strings")
        text = None
        if os.path.exists(p):
            with open(p, encoding="utf-8") as f:
                for line in f:
                    line = line.strip()
                    if line.startswith('"%s"' % KEY):
                        text = line.split("=", 1)[1].strip()
                        if text.startswith('"') and text.endswith('";'):
                            text = text[1:-2]
                        break
        if not text:
            fail.append((loc, "没读到译文"))
            continue
        r2 = sh(["asc", "localizations", "update", "--version", version_id,
                 "--locale", loc, "--whats-new", text])
        if r2.returncode == 0 and not r2.stderr.strip():
            ok += 1
        else:
            fail.append((loc, (r2.stderr or r2.stdout)[:100]))
    print("写入成功:", ok, "失败:", len(fail))
    for f in fail[:8]:
        print("  ✗", f)
    return 0 if not fail else 1


if __name__ == "__main__":
    sys.exit(main())
