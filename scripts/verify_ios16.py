#!/usr/bin/env python3
"""在 iOS 16 模拟器上验证私密记账的「打开即崩」修复（2026-11-11）。

背景
----
线上 1.0.18 / build 29 在用户的 iPhone 13（iOS 16.1）上打开即崩：
`SettingsView.swift` 里 `URL(string: "mailto:...?subject=\\(L("app_name"))%20Feedback")!`
在 iOS 16 及更早（旧的 RFC 1738/1808 解析）上对非 ASCII 返回 nil → 强制解包 → Swift trap。

iOS 17+ 改了 URL 解析（RFC 3986，自动百分号编码），所以模拟器要用 iOS 16 才能复现。

★ 关键：**模拟器语言必须设成中文**，否则 `L("app_name")` 是 ASCII
（en = "Private Money Tracker"），`URL(string:)` 不会返回 nil，复现不出来。

用法：
    python3 verify_ios16.py <simulator-udid>
"""
import json
import os
import subprocess
import sys
import time
import glob
import shutil

APP_BUNDLE = "com.freeledger.app"
CRASH_DIR = os.path.expanduser("~/Library/Logs/DiagnosticReports")


def sh(cmd, timeout=180, cwd=None):
    env = dict(os.environ)
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, env=env, cwd=cwd)
    return r.stdout, r.stderr, r.returncode


def udid_of(udid):
    return udid


def boot(udid):
    print("== 启动模拟器 ==")
    sh(["xcrun", "simctl", "boot", udid])
    sh(["xcrun", "simctl", "bootstatus", udid, "-b"], timeout=300)
    out, _, _ = sh(["xcrun", "simctl", "list", "devices"])
    for line in out.split("\n"):
        if udid in line:
            print("  ", line.strip()[:110])


def set_chinese(udid):
    """把模拟器设成中文 —— 否则 app_name 是 ASCII，崩溃复现不出来。"""
    print("== 设置语言为中文 ==")
    for args in (
        ["defaults", "write", "NSGlobalDomain", "AppleLanguages", "-array", "zh-Hans"],
        ["defaults", "write", "NSGlobalDomain", "AppleLocale", "-string", "zh_CN"],
    ):
        out, err, rc = sh(["xcrun", "simctl", "spawn", udid] + args)
        print("   %-46s %s" % (" ".join(args[2:]), "OK" if rc == 0 else "FAIL " + err[:80]))
    # 应用自己的偏好也设一份（有些 App 读 App 级的 AppleLanguages）
    out, err, rc = sh(["xcrun", "simctl", "spawn", udid, "defaults", "write",
                        APP_BUNDLE, "AppleLanguages", "-array", "zh-Hans"])
    print("   app 级别 AppleLanguages                 %s" % ("OK" if rc == 0 else "skip"))


def install(udid, app_path):
    print("== 安装 %s ==" % os.path.basename(app_path))
    out, err, rc = sh(["xcrun", "simctl", "install", udid, app_path], timeout=300)
    if rc != 0:
        print("  安装失败:", err[:300])
        return False
    print("   安装成功")
    return True


def clear_crashes():
    os.makedirs(CRASH_DIR, exist_ok=True)
    before = set(glob.glob(os.path.join(CRASH_DIR, "*.ips")))
    return before


def new_crashes(before):
    time.sleep(2)
    after = set(glob.glob(os.path.join(CRASH_DIR, "*.ips")))
    return [f for f in after - before if APP_BUNDLE in os.path.basename(f)]


def launch_and_watch(udid, label, wait_seconds=15):
    """启动 App，观察是否崩溃。"""
    print("== 启动 %s（等 %ds）==" % (label, wait_seconds))
    before = clear_crashes()
    # 先终止可能残留的
    sh(["xcrun", "simctl", "terminate", udid, APP_BUNDLE])

    pid_out, _, _ = sh(["xcrun", "simctl", "launch", udid, APP_BUNDLE])
    print("   ", pid_out.strip()[:160])

    alive = False
    for _ in range(wait_seconds):
        time.sleep(1)
        out, _, _ = sh(["xcrun", "simctl", "spawn", udid, "launchctl", "list"])
        if APP_BUNDLE in out:
            alive = True
    crashes = new_crashes(before)
    return alive, crashes


def main():
    if len(sys.argv) < 2:
        print("用法: verify_ios16.py <simulator-udid>")
        return 2
    udid = sys.argv[1]

    # ⚠️ 必须用 **Release** 模拟器产物：Debug 的二进制是 stub（真代码在 dSYM 里），
    #    strings 查不到 mailto，也不够接近真机行为。
    apps = {
        "build 28 (崩溃版, 修复前)": "/tmp/fl-dd28rel/Build/Products/Release-iphonesimulator/ColorFuLedger.app",
        "build 31 (修复版)": "/tmp/fl-dd31rel/Build/Products/Release-iphonesimulator/ColorFuLedger.app",
    }

    boot(udid)
    set_chinese(udid)

    results = {}
    for label, path in apps.items():
        if not os.path.exists(path):
            print("\n[跳过] %s —— 找不到 %s" % (label, path))
            continue
        sh(["xcrun", "simctl", "uninstall", udid, APP_BUNDLE])
        if not install(udid, path):
            continue
        alive, crashes = launch_and_watch(udid, label)
        print("   → 进程存活: %s | 新崩溃报告: %d" % ("是" if alive else "否", len(crashes)))
        for c in crashes:
            print("      ", c)
        results[label] = (alive, crashes)

    print("\n===== 结论 =====")
    for label, (alive, crashes) in results.items():
        verdict = "崩溃 ❌" if crashes else ("正常运行 ✅" if alive else "进程退出（需看崩溃报告）")
        print("  %-26s %s" % (label, verdict))
    return 0


if __name__ == "__main__":
    sys.exit(main())
