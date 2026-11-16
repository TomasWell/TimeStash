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
# 脚本自己的目录（必须在任何 cd 之前算 —— 见下方注释）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
# ⚠️ 2026-11-11 06:0x 实测修掉的**假绿**：原来这一段只是把 TEST SUCCEEDED/FAILED
# 打印出来，**从不据此决定退出码** → 测试有失败用例时脚本照样 exit 0。
# 现在把结果存进变量，最后统一判退出码（崩溃/失败 → 非 0）。
RESULT=$(grep -oE 'TEST (SUCCEEDED|FAILED)' "$LOG" | tail -1)
echo "$RESULT"
grep -E "Executed [0-9]+ test|Test run with [0-9]+ test" "$LOG" | tail -2
TEST_FAIL=0
if [ "$RESULT" != "TEST SUCCEEDED" ]; then
  # 「查不到 ≠ 没有」：RESULT 为空（xcodebuild 异常退出、只列了设备）也算失败，
  # 不能当成「跑完了」。这与下面「用例数 > 0」是同一道保险。
  echo "⛔ 测试结果不是 TEST SUCCEEDED（实际：${RESULT:-<没读到>}）—— **按失败算**"
  TEST_FAIL=1
fi

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
# ⚠️ 2026-11-16 P0 修正计数口径：原来 swift-testing 的汇总一旦存在就直接 return，
# **XCTest 的用例数被整个丢掉** → 实测 TimeStash 跑完 52 个用例（XCTest 49 + swift 3），
# 脚本却报「实际执行了 3 个用例」→ **提审前测试闸门据此判「用例太少」或看错基线**。
# 现在两个框架的用例数**相加**（swift-testing 汇总 + XCTest 各 bundle 的最大值）。
ST_COUNT=$(grep -oE 'Test run with [0-9]+ test' "$LOG" | grep -oE '[0-9]+' | head -1)
XC_COUNT=$(grep -oE 'Executed [0-9]+ tests?' "$LOG" | grep -oE '[0-9]+' | sort -rn | head -1)
[ -z "$ST_COUNT" ] && ST_COUNT=0
[ -z "$XC_COUNT" ] && XC_COUNT=0
COUNT=$((ST_COUNT + XC_COUNT))
if [ "$COUNT" = "0" ]; then
  echo "⛔ 没看到任何用例执行 —— xcodebuild 多半只列了设备就退出了（模拟器环境异常），**这一轮不算数**"
  echo "   处置：xcrun simctl shutdown ${DEV} && xcrun simctl erase ${DEV}，然后重跑"
  tail -20 "$LOG"
  exit 2
fi
echo "✅ 实际执行了 $COUNT 个用例（swift-testing $ST_COUNT + XCTest ${XC_COUNT}）"

# ⚠️ 2026-11-16 22:05 夜间档实测加：**「started 但从未报结果」的用例 = 静默丢失**。
#
# UI 测试 runner 进程中途自己死了（日志里 "Restarting after unexpected exit,
# crash, or test timeout"），xcodebuild 重启 runner 后**直接从下一个用例开始跑** ——
# 死在半路的那一个用例**既没 passed 也没 failed**，断言根本没跑完。
#
# ⚠️ 为什么旧的三道校验都发现不了：
#   「用例数 > 0」照样 > 0（丢失的用例已被计入）；
#   「0 failures」照样 = 0（它没报 failed）；「0 崩溃」照样 = 0（死的是 runner 不是 App）。
#   ⇒ 三道全绿，但有一个用例的断言根本没跑完 ⇒ 必须单独查。
#
# ⚠️ 判据逻辑单独放一个脚本 —— 内嵌在 .sh 里的正则第一版写错成贪婪匹配
#   （吞掉类名 → 空格永不匹配 → 一个都抓不到 → 永远说「没丢」= 假绿）。
if [ -f "$SCRIPT_DIR/check_lost_tests.py" ]; then
  if python3 "$SCRIPT_DIR/check_lost_tests.py" "$LOG"; then
    echo "✅ 没有静默丢失的用例"
  else
    SILENT_LOST=1
  fi
else
  echo "⚠️ 找不到 check_lost_tests.py，跳过「静默丢失」检查"
fi

echo
echo "=== 3. 崩溃检查 ==="
CRASH_AFTER=$(ls ~/Library/Logs/DiagnosticReports/${APP}-*.ips 2>/dev/null | wc -l | tr -d ' ')
NEW=$((CRASH_AFTER - CRASH_BEFORE))
if [ "$NEW" -gt 0 ]; then
  echo "⛔ 本轮新增 $NEW 份崩溃报告 —— **即使测试框架说通过，也按失败算**"
  # ⚠️ 2026-11-11 06:0x 实测修掉的**假绿**：原来这一行只是打印警告，
  # 脚本最后仍然 exit 0 → 「跑全量测试」的上层（提审前测试闸门）据此判 PASS
  # → **一个崩过的包会被提给 Apple**（DailyMe 2.1.0 就是这么被拒的）。
  # 现在记下失败标记，最后统一 exit 非 0。
  CRASH_FAIL=1
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

# ── 退出码：崩溃 / 测试失败 → 非 0（2026-11-11 06:0x 实测修） ──
# ⚠️ 这三道校验（用例数 > 0 / 崩溃检查 / 测试结果）以前**只打印不拦**，
# 上层只看退出码 → 全部假绿。现在统一在这里拦。
if [ "${SILENT_LOST:-0}" -gt 0 ]; then
  # ⛔ runner 重启导致用例静默丢失 —— 不能放行。
  #   放行前提是「所有用例都跑完了」，这里前提不成立 ⇒ 按失败算。
  echo "⛔ 本轮判定为失败（有用例静默丢失，runner 中途死掉）—— 退出码非 0"
  echo "   处置：重跑本轮测试；或 xcrun simctl shutdown ${DEV} && xcrun simctl erase ${DEV} 后重跑"
  exit 1
fi
if [ "${CRASH_FAIL:-0}" -gt 0 ] || [ "${TEST_FAIL:-0}" -gt 0 ]; then
  echo "⛔ 本轮判定为失败（崩溃=${CRASH_FAIL:-0} 测试结果=${TEST_FAIL:-0}）—— 退出码非 0"
  exit 1
fi

# 软链指向最新一轮，方便习惯性路径访问
ln -sf "$LOG" "/tmp/${APP}_test.log"
