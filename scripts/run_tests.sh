#!/bin/bash
# <APP> 统一测试入口
#
# 为什么必须有这个统一入口（2026-11-03 教训）：
# 之前没有统一入口 → 开发档自己拼 `xcodebuild test -destination 'name=iPhone 16 Pro'`，
# 结果**拿 iOS 18.2 去测一个声明支持 iOS 17 的 App** → iOS 17 用户的兼容性从没被验证过。
# 而且 `name=` 在本机有歧义（iPhone 15 Pro 有 17.4/17.5/18.2 三个）→ 一律用设备 ID。
#
# 三道校验（缺一不可）：
#   1. TEST SUCCEEDED / FAILED
#   2. **用例数 > 0** —— xcodebuild 在模拟器环境异常时会只打印一串设备列表然后 exit 0，
#      看起来「跑完了」其实一个用例都没跑。不查用例数就会误报「全绿」。
#   3. **本轮有没有崩溃** —— App 崩了就算失败，不许报「全绿」。
#
# 用法：bash scripts/run_tests.sh          （正常）
#      DEV=<设备ID> bash scripts/run_tests.sh   （换设备）
set -u
# ⚠️ 不要加 CODE_SIGNING_ALLOWED=NO —— 那会让 App Group entitlement 失效，
#    FileManager.containerURL(forSecurityApplicationGroupIdentifier:) 返回 nil，
#    守 entitlement 的用例会假失败（2026-11-03 实测：带签名全过，不带签名假失败）。


APP="TimeStash"
REPO="/Users/mac/TimeStash"
# 默认设备：iPhone 15 Pro / iOS 17.4
DEV="${DEV:-E844988F-921E-4F5A-A84F-CB945112AAE0}"

cd "$REPO/ios" || exit 1

# ── 互斥锁：同一台机器上不能有两个 xcodebuild 同时跑 ──
# ⚠️ 用**全局**锁（不分 App）：两个 App 同时跑测试会开两个模拟器设备、机器狂 load。
# 原因：两个测试共用同一个 DerivedData 和同一个模拟器 → 互相踢、结果污染
# （2026-11-03 实测：两轮并发时一轮报假失败）
LOCK=/tmp/xcodebuild_global.lock
if ! mkdir "$LOCK" 2>/dev/null; then
  if [ -f "$LOCK/pid" ] && kill -0 "$(cat "$LOCK/pid" 2>/dev/null)" 2>/dev/null; then
    echo "⛔ 已有另一个测试在跑（pid $(cat "$LOCK/pid")）—— 本轮跳过，不要并发"
    exit 3
  fi
  rm -rf "$LOCK" 2>/dev/null
  mkdir "$LOCK" 2>/dev/null || { echo "⛔ 拿不到锁，本轮跳过"; exit 3; }
fi
echo $$ > "$LOCK/pid"
trap 'rm -rf "$LOCK" 2>/dev/null' EXIT INT TERM

# 每轮一个独立日志文件（2026-11-08 修）：
# 之前所有轮次都写同一个 /tmp/<App>_test.log，后跑的覆盖先跑的 →
# 拿到一份旧进程的「失败」通知时，磁盘上的日志已经不是它那一轮了，
# 根本无法判断失败是旧代码还是真回归。
# 现在每轮写 <App>_test_<时间戳>.log，/tmp/<App>_test.log 只是软链到最新一轮。
STAMP=$(date +%Y%m%d-%H%M%S)
LOG="/tmp/${APP}_test_${STAMP}.log"

# 跑之前的崩溃基线
CRASH_BEFORE=$(ls ~/Library/Logs/DiagnosticReports/${APP}-*.ips 2>/dev/null | wc -l | tr -d ' ')

command -v xcodegen >/dev/null 2>&1 && xcodegen generate > /dev/null 2>&1

xcodebuild test -project ${APP}.xcodeproj -scheme ${APP} \
  -destination "platform=iOS Simulator,id=$DEV" \
  -derivedDataPath ./DerivedData > "$LOG" 2>&1

echo "=== 1. 测试结果 ==="
grep -oE 'TEST (SUCCEEDED|FAILED)' "$LOG" | tail -1
grep -E "Executed [0-9]+ test|Test run with [0-9]+ test" "$LOG" | tail -2

echo
echo "=== 2. 用例数校验（防假成功）==="
# 两种测试框架的输出格式都算：
#   swift-testing → "Test run with 176 tests in 14 suites"
#   XCTest        → "Executed 176 tests, with 0 failures"
# 只认其中一种会让另一种框架的项目永远误报「没跑用例」（2026-11-03 实测：
# PawRecord 是 XCTest，只匹配 swift-testing 的格式 → 176 个用例全过却被判失败）。
# 取**总用例数**，不能取最后一行：
#   - swift-testing → "Test run with 176 tests in 14 suites"（本身就是总数）
#   - XCTest        → 每个 bundle 一行 "Executed N tests"，最后一行是
#                    UITest bundle 的数字（常常只有 1），不是单测总数。
#     实测 TimeStash：单测 56 个 + UI 测试 1 个，tail -1 只拿到 1。
# 所以 XCTest 取所有 Executed 行里的**最大值**（每个 bundle 的总数行）
# 再加上 swift-testing 的汇总（两者可能并存）。
COUNT=$(grep -oE 'Test run with [0-9]+ test' "$LOG" | grep -oE '[0-9]+' | head -1)
[ -z "$COUNT" ] && COUNT=$(grep -oE 'Executed [0-9]+ tests?' "$LOG" | grep -oE '[0-9]+' | sort -rn | head -1)
if [ -z "$COUNT" ] || [ "$COUNT" = "0" ]; then
  echo "⛔ 没看到任何用例执行 —— xcodebuild 多半只列了设备就退出了（模拟器环境异常），**这一轮不算数**"
  echo "   处置：xcrun simctl shutdown ${DEV} && xcrun simctl erase ${DEV}，然后重跑"
  tail -20 "$LOG"
  exit 2
fi
echo "✅ 实际执行了 $COUNT 个用例"

echo
echo "=== 3. 崩溃检查 ==="
CRASH_AFTER=$(ls ~/Library/Logs/DiagnosticReports/${APP}-*.ips 2>/dev/null | wc -l | tr -d ' ')
NEW=$((CRASH_AFTER - CRASH_BEFORE))
if [ "$NEW" -gt 0 ]; then
  echo "⛔ 本轮新增 $NEW 份崩溃报告 —— **即使测试框架说通过，也按失败算**"
  python3 ~/.hermes/nightwork/crash_summary.py --app "$APP" --window-min 10 2>&1 | head -30
  echo "--- 真凶定位：崩溃栈里出现的函数名就是出问题的位置 ---"
else
  echo "✅ 本轮无崩溃"
fi

echo
echo "=== 错误摘要 ==="
grep -E "error:" "$LOG" | sed 's|.*/||' | sort -u | head -10
grep -E "' failed|recorded an issue" "$LOG" | sed 's|.*/||' | head -8
echo
echo "完整日志：$LOG"

# 软链指向最新一轮，方便习惯性路径访问
ln -sf "$LOG" "/tmp/${APP}_test.log"
