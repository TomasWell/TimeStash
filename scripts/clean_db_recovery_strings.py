#!/usr/bin/env python3
"""清理上一轮写坏的 db_recovery_* 条目（含被真实换行拆成多行的残骸）。

背景：2026-11-09 第一轮用 `hermes chat` 翻译失败（CLI 权限问题 + 模型连接失败），
提取到的是 prompt 里的英文原文，还把真实换行写进了 .strings，
导致一条条目被拆成多行、且同一键写了两遍。

本脚本：
  1. 把每个 locale 里所有 db_recovery_* 相关条目（含跨行残骸）整块删掉
  2. 重新写回正确的基准值（zh-Hans / zh-Hant 中文，en 英文）
  3. 其余 locale 留空，交给 translate-strings.py 翻译
"""
import glob
import os
import re
import sys

I18N = "/Users/mac/FreeLedger/ios/ColorFuLedger/i18n"
KEYS = ("db_recovery_title", "db_recovery_notice", "db_recovery_ok")

BASE = {
    "zh-Hans": {
        "db_recovery_title": "数据读取失败",
        "db_recovery_notice": "这次没能读出你的账本数据。原始数据文件已保留在：%@\\n\\nApp 现在是空账本，可以正常使用。你的原始数据没有被删除，请联系协助恢复。",
        "db_recovery_ok": "我知道了",
    },
    "zh-Hant": {
        "db_recovery_title": "資料讀取失敗",
        "db_recovery_notice": "這次沒能讀出你的帳本資料。原始資料檔案已保留在：%@\\n\\nApp 現在是空帳本，可以正常使用。你的原始資料沒有被刪除，請聯繫協助恢復。",
        "db_recovery_ok": "我知道了",
    },
    "en": {
        "db_recovery_title": "Data could not be read",
        "db_recovery_notice": "Your ledger data could not be read this time. The original data file has been kept at: %@\\n\\nThe app is now empty and works normally. Your original data was not deleted; please contact support to restore it.",
        "db_recovery_ok": "Got it",
    },
}


def strip_entries(path):
    """删掉所有 db_recovery_* 条目（可能跨多行），返回清理后的文本。"""
    with open(path, encoding="utf-8") as f:
        lines = f.read().splitlines(keepends=True)
    out = []
    i = 0
    removed = 0
    while i < len(lines):
        line = lines[i]
        stripped = line.strip()
        if any(stripped.startswith('"%s"' % k) for k in KEYS):
            removed += 1
            # 跨行的残骸：一直吃到出现 '";' 的行为止
            if not stripped.rstrip().endswith('";'):
                j = i + 1
                while j < len(lines):
                    if '";' in lines[j]:
                        j += 1
                        break
                    j += 1
                i = j
                continue
            i += 1
            continue
        out.append(line)
        i += 1
    return "".join(out), removed


def main():
    total_removed = 0
    for d in sorted(glob.glob(os.path.join(I18N, "*.lproj"))):
        loc = os.path.basename(d).replace(".lproj", "")
        p = os.path.join(d, "Localizable.strings")
        if not os.path.exists(p):
            continue
        s, removed = strip_entries(p)
        total_removed += removed
        if loc in BASE:
            block = "".join('"%s" = "%s";\n' % (k, v) for k, v in BASE[loc].items())
            if not s.endswith("\n"):
                s += "\n"
            s += block
        with open(p, "w", encoding="utf-8") as f:
            f.write(s)
    print("清理了 %d 条坏条目" % total_removed)

    # 复核
    bad = 0
    for d in sorted(glob.glob(os.path.join(I18N, "*.lproj"))):
        loc = os.path.basename(d).replace(".lproj", "")
        p = os.path.join(d, "Localizable.strings")
        with open(p, encoding="utf-8") as f:
            text = f.read()
        n = sum(text.count('"%s"' % k) for k in KEYS)
        want = 3 if loc in BASE else 0
        if n != want:
            print("  ⚠️ %s 有 %d 个 db_recovery 键（应为 %d）" % (loc, n, want))
            bad += 1
        # 跨行残骸检查：每个键后面必须同行闭合
        for k in KEYS:
            for m in re.finditer(r'"%s"\s*=\s*"' % re.escape(k), text):
                tail = text[m.end():m.end() + 400]
                if '";' not in tail.split("\n")[0]:
                    print("  ⚠️ %s 的 %s 被换行拆开了" % (loc, k))
                    bad += 1
                    break
    print("异常 locale 数:", bad)
    return 0


if __name__ == "__main__":
    sys.exit(main())
