#!/bin/bash
# TimeStash 商店截图正式产出脚本
#
# 为什么单独一个脚本（2026-11-08）：
# 截图曾经是 UI 测试里的一个类，输出直接写进 store-assets/screenshots/。
# 那样每次跑全量测试都会把**已交付的商店截图重新覆盖一遍**，
# 而且是在小屏模拟器上（1178×2556）—— 尺寸不在 App Store 官方列表里，
# 1290×2796 的正式素材被静默替换掉。
#
# 现在：
#   - UI 测试里的截图类只写 .screenshot-work/（临时目录，不入 git）
#   - 正式商店截图只能由本脚本产出，模拟器锁死在 6.7 寸（1290×2796）
#
# 用法：
#   bash scripts/make_store_screenshots.sh          # 出图到 store-assets/screenshots/
#   bash scripts/make_store_screenshots.sh --check  # 只校验现有素材的尺寸
set -euo pipefail

APP_DIR="/Users/mac/TimeStash"
OUT="$APP_DIR/store-assets/screenshots"
WORK="$APP_DIR/.screenshot-work"
# iPhone 15 Pro Max = 1290×2796 = APP_IPHONE_67 / APP_IPHONE_69（官方接受）
SIM="C5CA6D12-31E6-4DAD-BB69-5B4BB9FB12EE"
EXPECTED_W=1290
EXPECTED_H=2796

check_sizes() {
  local bad=0
  for f in "$OUT"/*.png; do
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

if [ "${1:-}" = "--check" ]; then
  echo "=== 校验商店截图尺寸 ==="
  check_sizes
  exit $?
fi

echo "=== 1. 启动 $SIM（6.7 寸，1290x2796）==="
xcrun simctl boot "$SIM" 2>/dev/null || true
sleep 8
xcrun simctl bootstatus "$SIM" -b 2>/dev/null || true

echo "=== 2. 跑截图用例（产物在 $WORK）==="
rm -rf "$WORK"
cd "$APP_DIR/ios"
xcodegen generate >/dev/null 2>&1
xcodebuild test \
  -project TimeStash.xcodeproj \
  -scheme TimeStash \
  -destination "platform=iOS Simulator,id=$SIM" \
  -only-testing:TimeStashUITests/ScreenshotCapture \
  2>&1 | grep -E '截图|XCTAssert|TEST (SUCCEEDED|FAILED)' || true

echo "=== 3. 搬运到正式目录 ==="
mkdir -p "$OUT"
cp "$WORK"/*.png "$OUT"/
rm -rf "$WORK"

echo "=== 4. 校验尺寸 ==="
check_sizes

echo "完成：$OUT"
