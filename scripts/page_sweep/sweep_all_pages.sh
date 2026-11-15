#!/bin/bash
# 时间收纳箱 · 全页面巡检（2026-11-16 建，抄 CommutePilot 那套成熟口径）
#
# 检查四件事：
#   1) 每屏关键词命中（该屏没被真正打开 → 当场报红）
#   2) 文字贴边 / 出界（被裁掉的字）
#   3) 文字互相重叠（两段字叠在一起）
#   4) 查重：content_hash（状态栏以下的像素指纹）—— 不同页同图 = 假绿
#
# ⚠️ 独立 derivedDataPath：不要和夜间档抢 ios/DerivedData（互杀，11-06 踩过）
# ⚠️ 跑之前确认没有别的 xcodebuild 在跑（pgrep + 看 Booted 模拟器 + xcresult mtime）
set -u
APP="TimeStash"
REPO="/Users/mac/TimeStash"
SIM="${SWEEP_SIM:-E844988F-921E-4F5A-A84F-CB945112AAE0}"   # iPhone 15 Pro
DD="${SWEEP_DD:-/tmp/timestash_sweep_dd}"
OUT="${SWEEP_OUT:-/tmp/timestash_page_sweep}"
BUNDLE="com.junxf.timestash"
PAGES_FILE="$REPO/scripts/page_sweep/pages.txt"

cd "$REPO" || exit 1
mkdir -p "$OUT"

echo "=== 构建并安装（独立 derivedDataPath: ${DD}）==="
( cd ios && xcodegen generate >/dev/null 2>&1 \
  && xcodebuild build -project ${APP}.xcodeproj -scheme ${APP} \
     -destination "platform=iOS Simulator,id=$SIM" -derivedDataPath "$DD" ) > "$OUT/build.log" 2>&1
if ! grep -q "BUILD SUCCEEDED" "$OUT/build.log"; then
  echo "⛔ 构建失败，看 $OUT/build.log"; tail -30 "$OUT/build.log"; exit 1
fi
echo "✅ 构建成功"

xcrun simctl boot "$SIM" 2>/dev/null
xcrun simctl bootstatus "$SIM" -b >/dev/null 2>&1
# 每轮从干净状态开始：上一轮遗留的 running 任务会让 resume 弹窗误触发
xcrun simctl uninstall "$SIM" "$BUNDLE" >/dev/null 2>&1
xcrun simctl install "$SIM" "$DD/Build/Products/Debug-iphonesimulator/${APP}.app" || exit 1
echo "✅ 已安装（先卸载 → 干净状态）"

OCR="$OUT/ocr"; SRC="$REPO/scripts/page_sweep/ocr_layout.swift"
if [ ! -x "$OCR" ] || [ "$SRC" -nt "$OCR" ]; then
  swiftc -O "$SRC" -o "$OCR" 2>"$OUT/ocr_build.log" || { echo "⛔ OCR 工具编译失败"; exit 1; }
fi

echo
echo "=== 逐屏截图 + OCR ==="
FAIL=0; DONE=0
: > "$OUT/hashes.txt"
while IFS='|' read -r name args must; do
  [ -z "$name" ] && continue
  case "$name" in \#*) continue;; esac
  # 先 terminate 并等它真的退干净（terminate 异步：紧跟着的 launch 会被忽略）
  xcrun simctl terminate "$SIM" "$BUNDLE" >/dev/null 2>&1
  for _ in $(seq 1 40); do
    if ! xcrun simctl terminate "$SIM" "$BUNDLE" >/dev/null 2>&1; then break; fi
    sleep 0.25
  done
  sleep 0.5
  # shellcheck disable=SC2086
  launchpid=$(xcrun simctl launch "$SIM" "$BUNDLE" $args 2>&1 | grep -oE '[0-9]+$')
  sleep 7
  shot="$OUT/$name.png"
  xcrun simctl io "$SIM" screenshot "$shot" >/dev/null 2>&1
  # ⛔ 0 字节截图守卫（simctl io 在设备忙时静默返回空文件，退出码 0）
  if [ ! -s "$shot" ] || [ "$(wc -c < "$shot")" -lt 10000 ]; then
    sleep 5
    xcrun simctl io "$SIM" screenshot "$shot" >/dev/null 2>&1
    if [ ! -s "$shot" ] || [ "$(wc -c < "$shot")" -lt 10000 ]; then
      echo "❌ $name 截图 0 字节/过小 —— 该屏没渲染出来"; FAIL=1
      echo "nodata_${name}" >> "$OUT/hashes.txt"
      continue
    fi
  fi
  out=$("$OCR" "$shot" 2>&1); echo "$out" > "$OUT/$name.txt"
  edge=$(echo "$out" | sed -n '/--- EDGE/,/--- OVERLAP/p' | grep -c "^  \[" || true)
  overlap=$(echo "$out" | sed -n '/--- OVERLAP/,/--- ALL/p' | grep -c "^  [0-9]" || true)
  cnt=$(echo "$out" | grep -oE "text_count=[0-9]+" | head -1)
  # 关键词判据：该屏根本没被打开 → 当场报红（不能等查重兜底）
  if [ -n "$must" ]; then
    if ! echo "$out" | grep -qiF "$must"; then
      echo "❌ $name 关键词「${must}」没命中 —— 这一屏可能没被真正打开"
      FAIL=1
    fi
  fi
  # 占位符扫描：snake_case 原始 key 出现在屏幕上 = 本地化断了
  if echo "$out" | grep -qE "(tab_|vault_|ledger_|stats_|timer_|new_task_|onboarding_|resume_|category_|milestone_)[a-z0-9_]+"; then
    echo "❌ $name 屏上出现原始本地化 key（snake_case）—— 本地化断了"
    echo "$out" | grep -oE "(tab_|vault_|ledger_|stats_|timer_|new_task_|onboarding_|resume_|category_|milestone_)[a-z0-9_]+" | head -3 | sed 's/^/     /'
    FAIL=1
  fi
  # 文字截断守卫：OCR 文本以省略号结尾 = 容器把字压扁了
  if echo "$out" | grep -qE '\.\.\.|…$'; then
    echo "⚠️  $name OCR 文本里有省略号 —— 疑似文字截断，人眼复核"
  fi
  # content_hash（状态栏以下像素指纹）—— 不是 PNG md5（会被时钟打穿）
  h=$(echo "$out" | grep -oE "content_hash=[0-9a-f]+" | head -1 | cut -d= -f2)
  if [ -z "$h" ]; then
    echo "⛔ $name OCR 没输出 content_hash（工具坏了）—— 查重无从谈起"
    h="nohash_${name}"; FAIL=1
  fi
  echo "$h $name" >> "$OUT/hashes.txt"
  if [ "$edge" -gt 0 ] || [ "$overlap" -gt 0 ]; then
    echo "❌ $name 贴边=$edge 重叠=$overlap $cnt"
    echo "$out" | sed -n '/--- EDGE/,/--- ALL/p' | grep "^  \[" | head -6 | sed 's/^/     /'
    FAIL=1
  else
    echo "✅ $name $cnt kw=$( [ -n "$must" ] && echo "$must" || echo - )"
  fi
  DONE=$((DONE+1))
done < "$PAGES_FILE"

echo
echo "=== 查重：不同页面截到同一张图 = 那屏没被真正打开 ==="
DUP=$(awk '{print $1}' "$OUT/hashes.txt" | sort | uniq -d)
if [ -n "$DUP" ]; then
  for d in $DUP; do
    echo "❌ 这些屏截出来是同一张图（至少一屏没被真正打开）："
    grep "^$d " "$OUT/hashes.txt" | sed 's/^/     /'
  done
  FAIL=1
else
  echo "✅ $DONE 屏内容互不相同"
fi

echo
echo "=== 空屏检测（文字数 < 6 = 疑似空状态，截图要人眼看）==="
for f in "$OUT"/*.txt; do
  [ -e "$f" ] || continue
  n=$(grep -oE "text_count=[0-9]+" "$f" | head -1 | grep -oE "[0-9]+")
  if [ -n "$n" ] && [ "$n" -lt 6 ]; then
    echo "⚠️  $(basename "$f" .txt) 只有 $n 段文字"
  fi
done

echo
echo "=== 覆盖 $DONE 屏，截图在 $OUT ==="
[ "$FAIL" -eq 0 ] && echo "✅ 机械检查全过（**仍需逐屏人眼看**）" || echo "⛔ 巡检发现问题"
exit $FAIL
