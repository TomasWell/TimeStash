#!/bin/bash
# TimeStash 商店截图正式产出脚本（支持多语言）
#
# 为什么单独一个脚本（2026-11-08）：截图曾经是 UI 测试里的一个类，
# 输出直接写进 store-assets/screenshots/。那样每次跑全量测试都会把
# **已交付的商店截图重新覆盖一遍**，而且是在小屏模拟器上（1178×2556）
# —— 尺寸不在 App Store 官方列表里，1290×2796 的正式素材被静默替换掉。
#
# ⚠️ 2026-11-16 P0 改造：原来**写死 zh-Hans** → ASC 实测 48 个 locale
# 的商店页**全部共用同一套中文截图**（10 个 checksum 被 48 locale 共用，
# 零专属图）→ 违反 Guideline 2.3.3（截图须展示该 locale 的实际界面）。
# 现在语言由环境变量传入，一份脚本出全部语言。
#
# 用法：
#   bash scripts/make_store_screenshots.sh                     # 只出 zh-Hans
#   bash scripts/make_store_screenshots.sh --all               # 出全部 48 个 locale
#   bash scripts/make_store_screenshots.sh --locale de-DE      # 只出指定 locale
#   bash scripts/make_store_screenshots.sh --check             # 只校验现有素材尺寸
set -euo pipefail

APP_DIR="/Users/mac/TimeStash"
OUT_ROOT="$APP_DIR/store-assets/screenshots"
WORK="$APP_DIR/.screenshot-work"
# iPhone 15 Pro Max = 1290×2796 = APP_IPHONE_67 / APP_IPHONE_69（官方接受）
SIM="${TS_SHOT_SIM:-C5CA6D12-31E6-4DAD-BB69-5B4BB9FB12EE}"
EXPECTED_W=1290
EXPECTED_H=2796

# 「ASC 商店页 locale | App 内 lproj | 系统 locale」
# ⚠️ 映射依据是 App 自己的 i18n 目录（`ios/TimeStash/i18n/*.lproj`），
#    不是 ASC 列表 —— ASC 不认裸语言码（`no`→`nb`、`ur-PK`→`ur` 等）。
PAIRS="
zh-Hans|zh-Hans|zh_CN
zh-Hant|zh-Hant|zh_TW
en-US|en|en_US
en-GB|en|en_GB
en-AU|en|en_AU
en-CA|en|en_CA
ar-SA|ar|ar_SA
bn-BD|bn|bn_BD
cs|cs|cs_CZ
da|da|da_DK
de-DE|de|de_DE
el|el|el_GR
es-ES|es|es_ES
fi|fi|fi_FI
fr-FR|fr|fr_FR
gu-IN|gu|gu_IN
he|he|he_IL
hi|hi|hi_IN
hr|hr|hr_HR
hu|hu|hu_HU
id|id|id_ID
it|it|it_IT
ja|ja|ja_JP
kn-IN|kn|kn_IN
ko|ko|ko_KR
ml-IN|ml|ml_IN
mr-IN|mr|mr_IN
ms|ms|ms_MY
nl-NL|nl|nl_NL
no|nb|nb_NO
pa-IN|pa|pa_IN
pl|pl|pl_PL
pt-BR|pt-BR|pt_BR
pt-PT|pt-PT|pt_PT
ro|ro|ro_RO
ru|ru|ru_RU
sk|sk|sk_SK
sl-SI|sl|sl_SI
sv|sv|sv_SE
ta-IN|ta|ta_IN
te-IN|te|te_IN
th|th|th_TH
tr|tr|tr_TR
uk|uk|uk_UA
ur-PK|ur|ur_PK
vi|vi|vi_VN
"

check_sizes() {
  local dir="$1" bad=0
  for f in "$dir"/*.png; do
    [ -e "$f" ] || continue
    w=$(python3 -c "import struct;d=open('$f','rb').read(26);print(struct.unpack('>II',d[16:24])[0])")
    h=$(python3 -c "import struct;d=open('$f','rb').read(26);print(struct.unpack('>II',d[16:24])[1])")
    if [ "$w" = "$EXPECTED_W" ] && [ "$h" = "$EXPECTED_H" ]; then
      echo "  ✅ $(basename "$f") ${w}x${h}"
    else
      echo "  ❌ $(basename "$f") ${w}x${h}  （应为 ${EXPECTED_W}x${EXPECTED_H}）"
      bad=$((bad + 1))
    fi
  done
  echo "不合格: $bad"
  return $bad
}

# 拍一个 locale 的 10 张图 → $2（输出目录）
shoot_locale() {
  local asc_locale="$1" app_lang="$2" sys_locale="$3" dest="$4"
  mkdir -p "$dest"

  echo "=== 拍 ${asc_locale}（App 内语言 ${app_lang}）==="
  rm -rf "$WORK"
  mkdir -p "$WORK"
  cd "$APP_DIR/ios" || return 1

  # ⚠️ 语言靠 -AppleLanguages 启动参数切换（改 App domain 的 AppleLanguages
  #    对 Bundle.main 的语言协商不生效 —— 2026-11-10 DailyMe 实测）。
  #    这里由 ScreenshotCapture.swift 读 TS_SHOT_LANG 环境变量传入。
  TS_SHOT_LANG="$app_lang" TS_SHOT_LOCALE="$sys_locale" \
  xcodebuild test \
    -project TimeStash.xcodeproj \
    -scheme TimeStash \
    -destination "platform=iOS Simulator,id=$SIM" \
    -only-testing:TimeStashUITests/ScreenshotCapture \
    > "$WORK/xcodebuild.log" 2>&1 || true

  local n=$(ls "$WORK"/*.png 2>/dev/null | wc -l | tr -d ' ')
  if [ "$n" -lt 5 ]; then
    echo "  ⛔ 只拍到 $n 张（应为 10）—— 看 $WORK/xcodebuild.log"
    tail -25 "$WORK/xcodebuild.log"
    return 1
  fi
  # 0 字节 = simctl 在设备没起来时静默产出空文件（2026-11-10 DailyMe 实测）
  local empty=0
  for f in "$WORK"/*.png; do
    [ -e "$f" ] || continue
    if [ "$(stat -f%z "$f")" -lt 10000 ]; then
      echo "  ⛔ $(basename "$f") 是 0 字节/异常小 → 丢弃"
      rm -f "$f"; empty=$((empty+1))
    fi
  done
  if [ "$empty" -gt 0 ]; then
    echo "  ⛔ 丢了 $empty 张异常图（设备没真正起来）"
    return 1
  fi
  cp "$WORK"/*.png "$dest"/
  rm -rf "$WORK"
  echo "  ✅ $n 张 → $dest"
  return 0
}

MODE="${1:-}"
case "$MODE" in
  --check)
    echo "=== 校验商店截图尺寸 ==="
    for d in "$OUT_ROOT"/*/; do
      [ -d "$d" ] || continue
      echo "--- $(basename "$d") ---"
      check_sizes "$d" || true
    done
    check_sizes "$OUT_ROOT" || true
    exit 0
    ;;
  --locale)
    ONLY="$2"
    ;;
  --all)
    ONLY=""
    ;;
  "")
    ONLY="zh-Hans"
    ;;
  *)
    echo "未知参数：$MODE"
    exit 1
    ;;
esac

echo "=== 启动 ${SIM}（6.7 寸，${EXPECTED_W}x${EXPECTED_H}）==="
xcrun simctl boot "$SIM" 2>/dev/null || true
sleep 8
xcrun simctl bootstatus "$SIM" -b 2>/dev/null || true

cd "$APP_DIR/ios" || exit 1
command -v xcodegen >/dev/null 2>&1 && xcodegen generate >/dev/null 2>&1

FAILED_FILE="$APP_DIR/.screenshot-failed.txt"
: > "$FAILED_FILE"
COUNT_FILE="$APP_DIR/.screenshot-count.txt"
echo 0 > "$COUNT_FILE"
# ⚠️ 原来用 `echo "$PAIRS" | while ...` —— 管道让 while 跑在**子 shell** 里
# → COUNT/FAILED 的赋值出不来 → 脚本永远报「完成，失败 locale：无」。
# 改成「先写临时文件，再 while read < 文件」→ 变量在当前 shell 里生效。
PAIRS_FILE="$APP_DIR/.screenshot-pairs.txt"
printf '%s\n' "$PAIRS" | grep -v '^[[:space:]]*$' > "$PAIRS_FILE"

while IFS='|' read -r asc app_lang sys_locale; do
  [ -z "$asc" ] && continue
  if [ -n "$ONLY" ] && [ "$asc" != "$ONLY" ]; then continue; fi
  dest="$OUT_ROOT/$asc"
  if shoot_locale "$asc" "$app_lang" "$sys_locale" "$dest"; then
    COUNT=$(cat "$COUNT_FILE")
    echo $((COUNT+1)) > "$COUNT_FILE"
    check_sizes "$dest" || echo "  ⚠️ $asc 尺寸有问题"
  else
    echo "$asc" >> "$FAILED_FILE"
  fi
done < "$PAIRS_FILE"

COUNT=$(cat "$COUNT_FILE")
FAILED=$(cat "$FAILED_FILE" | tr '\n' ' ')
rm -f "$PAIRS_FILE" "$COUNT_FILE" "$FAILED_FILE"

echo
echo "完成。成功 $COUNT 个 locale。失败 locale：${FAILED:-无}"
