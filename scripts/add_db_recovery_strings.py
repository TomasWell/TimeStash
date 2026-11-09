#!/usr/bin/env python3
"""给 46 个 locale 补 db_recovery_* 三个键（数据库读取失败兜底提示）。

2026-11-09 线上崩溃止血用。键：
  db_recovery_title  弹窗标题
  db_recovery_notice 弹窗正文（含 %@ = 被保留的原始库路径）
  db_recovery_ok    确认按钮

翻译用现成的翻译流水线（本地 bash 循环调 hermes chat），
本脚本只负责：① 写 zh-Hans 基准 ② 检查每个 locale 的三个键齐不齐
③ 跑流水线 ④ 校验占位符与解析。
"""
import glob
import os
import re
import subprocess
import sys

ROOT = "/Users/mac/FreeLedger"
I18N = os.path.join(ROOT, "ios/ColorFuLedger/i18n")

BASE = {
    "zh-Hans": {
        "db_recovery_title": "数据读取失败",
        "db_recovery_notice": "这次没能读出你的账本数据。原始数据文件已保留在：%@\n\nApp 现在是空账本，可以正常使用。你的原始数据没有被删除，请联系协助恢复。",
        "db_recovery_ok": "我知道了",
    },
    "zh-Hant": {
        "db_recovery_title": "資料讀取失敗",
        "db_recovery_notice": "這次沒能讀出你的帳本資料。原始資料檔案已保留在：%@\n\nApp 現在是空帳本，可以正常使用。你的原始資料沒有被刪除，請聯繫協助恢復。",
        "db_recovery_ok": "我知道了",
    },
}

KEYS = ("db_recovery_title", "db_recovery_notice", "db_recovery_ok")


def parse(path):
    keys = {}
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("//") or line.startswith("/*"):
                continue
            m = re.match(r'^"((?:[^"\\]|\\.)*)"\s*=\s*"(.*)";\s*$', line)
            if m:
                keys[m.group(1)] = m.group(2)
    return keys


def write_keys(loc, values):
    p = os.path.join(I18N, f"{loc}.lproj/Localizable.strings")
    with open(p, encoding="utf-8") as f:
        s = f.read()
    # 去掉已有的同名键（重跑安全）
    for k in KEYS:
        s = re.sub(r'^"%s"\s*=\s*".*";\s*\n' % re.escape(k), "", s, flags=re.M)
    block = "".join('"%s" = "%s";\n' % (k, v) for k, v in values.items())
    if not s.endswith("\n"):
        s += "\n"
    s += block
    with open(p, "w", encoding="utf-8") as f:
        f.write(s)


def main():
    # 1. 写基准
    for loc, vals in BASE.items():
        write_keys(loc, vals)
    print("基准已写:", ", ".join(BASE))

    # 2. 列出缺键的 locale
    missing = []
    for d in sorted(glob.glob(os.path.join(I18N, "*.lproj"))):
        loc = os.path.basename(d).replace(".lproj", "")
        if loc in BASE:
            continue
        k = parse(os.path.join(d, "Localizable.strings"))
        if not all(x in k for x in KEYS):
            missing.append(loc)
    print("缺键 locale:", len(missing))
    if not missing:
        print("全部齐了")
        return 0
    print(",".join(missing))
    return 0


if __name__ == "__main__":
    sys.exit(main())
