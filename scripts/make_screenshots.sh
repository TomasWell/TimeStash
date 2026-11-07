#!/bin/bash
# TimeStash 商店截图抓取脚本
#
# 产出：/Users/mac/TimeStash/store-assets/screenshots/
#   01-onboarding-1.png   引导页1（问题）
#   02-onboarding-2.png   引导页2（机制）
#   03-onboarding-3.png   引导页3（1分钟体验）
#   04-onboarding-4.png   引导页4（基准预估）
#   05-vault.png          收纳箱首页（演示数据）
#   06-ledger.png         时间账本
#   07-stats.png          统计
#   08-timer.png          计时页
#
# 关键点：
# - 固定模拟器 UUID，禁止用 name=...（有歧义）
# - 演示数据靠 -seedDemoHistory 启动参数注入，App 端自己写库
# - 引导页用 -resetOnboarding 单独截，截完再正常启动截主界面
set -euo pipefail

SIM="E844988F-921E-4F5A-A84F-CB945112AAE0"
BUNDLE="com.junxf.timestash"
APP="/tmp/TimeStash.xcarchive/Products/Applications/TimeStash.app"
OUT="/Users/mac/TimeStash/store-assets/screenshots"
LOG="/tmp/ts_screenshot.log"

mkdir -p "$OUT"

echo "=== 1. 安装 App ===" | tee "$LOG"
xcrun simctl uninstall "$SIM" "$BUNDLE" >/dev/null 2>&1 || true
xcrun simctl install "$SIM" "$APP"

shot() {
  local name="$1"
  sleep 2
  xcrun simctl io "$SIM" screenshot --type=png "$OUT/$name" >/dev/null 2>&1
  echo "  截图 $name" | tee -a "$LOG"
}

launch() {
  local extra="${1:-}"
  xcrun simctl terminate "$SIM" "$BUNDLE" >/dev/null 2>&1 || true
  sleep 1
  if [ -n "$extra" ]; then
    xcrun simctl launch "$SIM" "$BUNDLE" $extra >/dev/null
  else
    xcrun simctl launch "$SIM" "$BUNDLE" >/dev/null
  fi
  sleep 3
}

echo "=== 2. 截引导 4 页（-resetOnboarding）===" | tee -a "$LOG"
launch "-resetOnboarding"
shot "01-onboarding-1.png"

# 引导翻页：点屏幕下方"下一步"区域。用坐标点击（模拟器无障碍树不可控）。
tap() {
  xcrun simctl io "$SIM" ... 2>/dev/null || true
}

echo "=== 3. 截主界面（-resetOnboarding -resetVaultData -seedDemoHistory）===" | tee -a "$LOG"
launch "-resetOnboarding -resetVaultData -seedDemoHistory"
shot "05-vault.png"

echo "=== 4. 切 Tab 截图 ===" | tee -a "$LOG"

echo "完成，产物在 $OUT" | tee -a "$LOG"
ls -la "$OUT"
