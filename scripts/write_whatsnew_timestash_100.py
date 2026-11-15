#!/usr/bin/env python3
"""给时间收纳箱 1.0 写 What's New（48 个 locale），然后可提审。

1.0 是首版，What's New 本可留空 —— 但填上更完整，且避免提交审核后版本层被锁。
内容口径：首版功能说明（把时间当成钱来记 / 提前完成存进箱子 / 长期图表）。
中英繁直接写死，其余语言走 MiniMax 直连翻译（translate-strings.py，不走 hermes chat）。
"""
import json
import os
import shutil
import subprocess
import sys

APP = "6832234671"
VID = "46a2877b-8ab7-4884-8b21-cfc4583ad3a9"
KEY = "whatsnew_timestash_100"
TMP = "/tmp/ts_whatsnew_i18n"

WHATS_NEW = {
    "zh-Hans": "时间收纳箱首版：把时间当成钱来记。给每件事设定目标时长，提前完成，省下的时间就存进箱子里；长期图表告诉你一共攒下了多少。",
    "zh-Hant": "時間收納箱首版：把時間當成錢來記。給每件事設定目標時長，提前完成，省下的時間就存進箱子裡；長期圖表告訴你一共攢下了多少。",
    "en": "First release of TimeStash: Save Time. Track your tasks like you track money — set a target duration, finish early, and the time you saved goes into your vault. Long-term charts show how much you've banked.",
}


def sh(cmd, cwd=None):
    env = dict(os.environ)
    env["PATH"] = "/Users/mac/.blitz/bin:" + env.get("PATH", "")
    env["ASC_TIMEOUT"] = "120s"
    return subprocess.run(cmd, capture_output=True, text=True, env=env, cwd=cwd)


def main():
    out = sh(["asc", "localizations", "list", "--version", VID, "--output", "json"]).stdout
    try:
        items = json.loads(out).get("data", [])
    except Exception as e:
        print("读 localizations 失败:", e, out[:200])
        return 1
    print("版本层 locale 数:", len(items))

    need = []
    for it in items:
        loc = it.get("attributes", {}).get("locale")
        if loc in WHATS_NEW:
            r = sh(["asc", "localizations", "update", "--version", VID,
                    "--locale", loc, "--whats-new", WHATS_NEW[loc]])
            ok = r.returncode == 0 and not r.stderr.strip()
            print("  %-10s %s" % (loc, "✓" if ok else "✗ " + r.stderr[:110]))
        else:
            need.append(loc)
    print("需要翻译:", len(need))
    if not need:
        return 0

    shutil.rmtree(TMP, ignore_errors=True)
    os.makedirs(TMP, exist_ok=True)
    for loc in need:
        d = os.path.join(TMP, "%s.lproj" % loc)
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, "Localizable.strings"), "w", encoding="utf-8") as f:
            f.write('"%s" = "%s";\n' % (KEY, WHATS_NEW["en"]))
    base = os.path.join(TMP, "en.lproj")
    os.makedirs(base, exist_ok=True)
    with open(os.path.join(base, "Localizable.strings"), "w", encoding="utf-8") as f:
        f.write('"%s" = "%s";\n' % (KEY, WHATS_NEW["en"]))

    r = sh(["python3", "translate-strings.py", "--i18n-dir", TMP, "--base", "en",
            "--batch", "2", "--progress-file", "/tmp/ts_whatsnew_progress.json"],
           cwd="/Users/mac/FreeLedger/scripts/i18n")
    print(r.stdout[-600:])
    if r.returncode != 0:
        print("翻译报错:", r.stderr[-400:])

    ok, fail = 0, []
    for loc in need:
        p = os.path.join(TMP, "%s.lproj" % loc, "Localizable.strings")
        text = None
        if os.path.exists(p):
            for line in open(p, encoding="utf-8"):
                line = line.strip()
                if line.startswith('"%s"' % KEY):
                    text = line.split("=", 1)[1].strip()
                    if text.startswith('"') and text.endswith('";'):
                        text = text[1:-2]
                    break
        if not text:
            fail.append((loc, "没读到译文"))
            continue
        r2 = sh(["asc", "localizations", "update", "--version", VID,
                 "--locale", loc, "--whats-new", text])
        if r2.returncode == 0 and not r2.stderr.strip():
            ok += 1
        else:
            fail.append((loc, (r2.stderr or r2.stdout)[:100]))
    print("写入成功: %d 失败: %d" % (ok, len(fail)))
    for f in fail[:8]:
        print("  ✗", f)
    return 0 if not fail else 1


if __name__ == "__main__":
    sys.exit(main())
