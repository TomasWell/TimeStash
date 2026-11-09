#!/bin/bash
# 给 FreeLedger 的 44 个 locale 补 db_recovery_* 三个键。
#
# 为什么用本地 bash 循环而不是 delegate_task（skill 里记过）：
# delegate_task 派 agent 一次生成 44 语言 × 3 键必败（90s 超时 / MiniMax 429 限流）。
# 正确做法：逐语言单独调 `hermes chat -q`，串行跑，每个语言落盘后再跑下一个。
set -uo pipefail

I18N="/Users/mac/FreeLedger/ios/ColorFuLedger/i18n"
OUTDIR="/tmp/db_recovery_tr"
mkdir -p "$OUTDIR"

LOCALES="ar bn ca cs da de el en es fi fil fr gu he hi hr hu id it ja kn ko ml mr ms nb nl or pa pl pt-BR pt-PT ro ru sk sl sv ta te th tr uk ur vi"

PROMPT='Translate these three iOS .strings entries into the language identified by the code LOCALE_CODE. Keep the %@ placeholder exactly as %@. Keep the newline as a literal backslash-n (\\n) inside the string. Output ONLY three lines in the format "key" = "value"; with no commentary, no markdown fences, and no extra keys.

"db_recovery_title" = "Data could not be read";
"db_recovery_notice" = "Your ledger data could not be read this time. The original data file has been kept at: %@\\n\\nThe app is now empty and works normally. Your original data was not deleted; please contact support to restore it.";
"db_recovery_ok" = "Got it";'

for code in $LOCALES; do
  TARGET="$I18N/$code.lproj/Localizable.strings"
  [ -f "$TARGET" ] || { echo "跳过 $code（没有 .lproj）"; continue; }
  # 已经有就跳过（可重复执行）
  if grep -q '"db_recovery_title"' "$TARGET"; then
    echo "已有 $code —— 跳过"
    continue
  fi
  echo "--- 翻译 $code ---"
  P="$PROMPT" LOCALE_CODE="$code" hermes chat -q "$PROMPT" -m m3fp --provider minimax-cn \
      > "$OUTDIR/$code.log" 2>&1
  # 从输出里抠出三行，写进 .strings
  python3 - "$OUTDIR/$code.log" "$TARGET" "$code" <<'PY'
import re, sys
log_path, target, code = sys.argv[1], sys.argv[2], sys.argv[3]
raw = open(log_path, encoding='utf-8', errors='replace').read()
keys = ("db_recovery_title", "db_recovery_notice", "db_recovery_ok")
vals = {}
for k in keys:
    m = re.search(r'"%s"\s*=\s*"(.*)"\s*;' % re.escape(k), raw, re.S)
    if m:
        vals[k] = m.group(1)
if len(vals) != 3:
    print("  ✗ %s 只抠到 %d 个键，跳过" % (code, len(vals)))
    sys.exit(0)
if "%@" not in vals["db_recovery_notice"]:
    print("  ✗ %s 丢了 %%@ 占位符，跳过" % code)
    sys.exit(0)
s = open(target, encoding='utf-8').read()
if not s.endswith("\n"):
    s += "\n"
s += "".join('"%s" = "%s";\n' % (k, vals[k]) for k in keys)
open(target, 'w', encoding='utf-8').write(s)
print("  ✓ %s 写入 3 个键" % code)
PY
done
echo "完成"
