#!/usr/bin/env python3
"""在 iOS 16.4 模拟器上真实走一遍私密记账 build 31：装 → 启 → 截图。

为什么这么做（2026-11-11）：
- 私密记账**没有 UI 测试 target**，UI 层从没在 iOS 16 上验证过
- SwiftUI 的 List / Form / NavigationStack 在 iOS 16 与 17 上行为差异大，
  单元测试抓不到布局类问题
- 用户本人就是 iOS 16 用户，这一条直接关系到他的使用

用法：python3 smoke_ios16_ui.py <simulator-udid>
"""
import os
import subprocess
import sys
import time

APP = "com.freeledger.app"
SHOTS = "/Users/mac/TimeStash/docs/ios16-crash-evidence"


def sh(cmd, timeout=180):
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    return r.stdout.strip(), r.stderr.strip(), r.returncode


def main():
    if len(sys.argv) < 2:
        print("用法: smoke_ios16_ui.py <simulator-udid>")
        return 2
    udid = sys.argv[1]
    app = "/tmp/fl-dd31rel/Build/Products/Release-iphonesimulator/ColorFuLedger.app"
    os.makedirs(SHOTS, exist_ok=True)

    print("== 系统语言 ==")
    out, _, _ = sh(["xcrun", "simctl", "spawn", udid, "defaults", "read",
                    "NSGlobalDomain", "AppleLanguages"])
    print("  ", out.replace("\n", " "))

    print("== 卸载旧的（清 UserDefaults 里的 app_language）==")
    sh(["xcrun", "simctl", "uninstall", udid, APP])
    # 明确清掉上次可能存下的语言选择
    sh(["xcrun", "simctl", "spawn", udid, "defaults", "delete", APP, "app_language"])

    print("== 安装 build 31 ==")
    out, err, rc = sh(["xcrun", "simctl", "install", udid, app], timeout=300)
    print("  ", "成功" if rc == 0 else "失败: " + err[:200])

    print("== 启动 ==")
    out, err, rc = sh(["xcrun", "simctl", "launch", udid, APP])
    print("  ", out[:160] or err[:160])

    time.sleep(12)

    alive = False
    out, _, _ = sh(["xcrun", "simctl", "spawn", udid, "launchctl", "list"])
    alive = APP in out
    print("== 12 秒后进程存活: %s ==" % ("是" if alive else "否"))

    print("== 截图 ==")
    shot = os.path.join(SHOTS, "ios16.4-build31-launch.png")
    out, err, rc = sh(["xcrun", "simctl", "io", udid, "screenshot", shot], timeout=120)
    print("  ", shot, os.path.getsize(shot) if os.path.exists(shot) else "失败 " + err[:120])

    # 崩溃报告检查
    import glob
    crashes = [f for f in glob.glob(os.path.expanduser("~/Library/Logs/DiagnosticReports/*.ips"))
               if APP in os.path.basename(f)
               and os.path.getmtime(f) > time.time() - 600]
    print("== 新崩溃报告: %d ==" % len(crashes))
    for c in crashes:
        print("  ", c)

    print("\n== 结论 ==")
    print("  进程存活: %s | 崩溃: %d" % ("是" if alive else "否", len(crashes)))
    return 0 if alive and not crashes else 1


if __name__ == "__main__":
    sys.exit(main())
