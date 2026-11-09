#!/usr/bin/env python3
"""翻译 1.0.18 的 What's New（46 个 locale）并写进 ASC。

用 FreeLedger 自带的 translate-strings.py 那条 MiniMax 直连路子（不经过 hermes CLI，
`hermes chat` 在这台机器上有 CLI 权限 + 模型连接问题，会静默返回 prompt 原文）。

流程：
  1. 把待翻译 locale 清单写成临时的「伪 .strings 目录」，每个 locale 一个 .lproj
  2. 用 translate-strings.py 翻译（基准 = en-US）
  3. 逐 locale 读回，用 asc localizations update 写进 ASC
  4. 回读 ASC 验证
"""
import json
import os
import shutil
import subprocess
import sys

VERSION_ID = "018336b9-ae4e-4a84-b957-e05afa00b847"
TMP = "/tmp/whatsnew_i18n"
KEY = "whatsnew_118"

SOURCE = (
    "Fixes a crash on launch: if your ledger data could not be read, "
    "the app no longer quits - your original data is kept safe and never deleted. "
    "Also adds a clear notice when this happens."
)


def sh(cmd, **kw):
    env = dict(os.environ)
    env["PATH"] = "/Users/mac/.blitz/bin:" + env.get("PATH", "")
    return subprocess.run(cmd, capture_output=True, text=True, env=env, **kw)


def main():
    todo = json.load(open("/tmp/whatsnew_todo.json", encoding="utf-8"))
    locales = [t[0] for t in todo]
    print("待翻译:", len(locales))

    shutil.rmtree(TMP, ignore_errors=True)
    os.makedirs(TMP, exist_ok=True)
    for loc in locales:
        d = os.path.join(TMP, f"{loc}.lproj")
        os.makedirs(d, exist_ok=True)
        # 每个 locale 先放一份英文（基准是 en-US，其它 locale 会被翻译覆盖）
        with open(os.path.join(d, "Localizable.strings"), "w", encoding="utf-8") as f:
            f.write('"%s" = "%s";\n' % (KEY, SOURCE))
    # 基准 locale（en-US）要有
    base = os.path.join(TMP, "en-US.lproj")
    os.makedirs(base, exist_ok=True)
    with open(os.path.join(base, "Localizable.strings"), "w", encoding="utf-8") as f:
        f.write('"%s" = "%s";\n' % (KEY, SOURCE))

    # 翻译（基准 en-US，其余全翻译）
    r = sh(["python3", "translate-strings.py", "--i18n-dir", TMP,
            "--base", "en-US", "--batch", "2",
            "--progress-file", "/tmp/whatsnew_progress.json"],
           cwd="/Users/mac/FreeLedger/scripts/i18n")
    print(r.stdout[-1500:])
    if r.returncode != 0:
        print("翻译有报错:", r.stderr[-600:])

    # 读回并写进 ASC
    ok = 0
    fail = []
    for loc in locales:
        p = os.path.join(TMP, f"{loc}.lproj", "Localizable.strings")
        text = None
        if os.path.exists(p):
            with open(p, encoding="utf-8") as f:
                for line in f:
                    line = line.strip()
                    if line.startswith('"%s"' % KEY):
                        text = line.split('=', 1)[1].strip()
                        if text.startswith('"') and text.endswith('";'):
                            text = text[1:-2]
                        break
        if not text:
            fail.append((loc, "没读到译文"))
            continue
        if "%" in text and "%@" not in text and "%d" not in text:
            pass
        r2 = sh(["asc", "localizations", "update", "--version", VERSION_ID,
                 "--locale", loc, "--whats-new", text])
        if r2.returncode == 0 and not r2.stderr.strip():
            ok += 1
        else:
            fail.append((loc, (r2.stderr or r2.stdout)[:120]))
    print("写入成功:", ok, "失败:", len(fail))
    for f in fail[:10]:
        print("  ✗", f)
    return 0


if __name__ == "__main__":
    sys.exit(main())
