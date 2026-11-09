#!/usr/bin/env python3
"""最忠实的升级复现：build 27（1.0.16 线上版）→ build 28（1.0.17 线上版）。

步骤：
  1. 装 build 27，启动，让它建出**真实的完整 v17 库**（含默认分类/账户/账本）
  2. 灌几笔交易，模拟真实用户数据
  3. 用 build 28 覆盖安装（模拟 App Store 更新）
  4. 启动 → 看崩不崩 + 抓崩溃日志

这是唯一能证明「真实用户升级路径」的复现方式：
自己造 schema 会漏掉真实库里那些「代码没预料到但真实存在」的东西。
"""
import os
import shutil
import subprocess
import sqlite3
import sys
import time

SIM = "E844988F-921E-4F5A-A84F-CB945112AAE0"
BUNDLE = "com.freeledger.app"
APP27 = "/tmp/fl-dd27/Build/Products/Debug-iphonesimulator/ColorFuLedger.app"
APP28 = "/tmp/fl-dd28/Build/Products/Debug-iphonesimulator/ColorFuLedger.app"


def sh(*args, **kw):
    return subprocess.run(args, capture_output=True, text=True, **kw)


def data_dir():
    return sh("xcrun", "simctl", "get_app_container", SIM, BUNDLE, "data").stdout.strip()


def db_path():
    return os.path.join(data_dir(), "Library", "Application Support", "freeledger.sqlite")


def is_running():
    out = sh("xcrun", "simctl", "spawn", SIM, "launchctl", "list").stdout
    return "freeledger" in out.lower()


def launch_and_watch(label, wait=12):
    sh("xcrun", "simctl", "terminate", SIM, BUNDLE)
    time.sleep(1)
    p = sh("xcrun", "simctl", "launch", SIM, BUNDLE)
    print("  %s launch: %s" % (label, (p.stdout or p.stderr).strip()))
    time.sleep(wait)
    alive = is_running()
    print("  %s 进程还活着: %s" % (label, alive))
    return alive


def seed_transactions():
    path = db_path()
    con = sqlite3.connect(path)
    cur = con.cursor()
    acc = cur.execute("SELECT id FROM accounts LIMIT 1").fetchone()
    cat = cur.execute("SELECT id FROM categories WHERE type='expense' LIMIT 1").fetchone()
    if not acc or not cat:
        print("  没有默认账户/分类，跳过灌数据")
        con.close()
        return
    rows = []
    for i in range(8):
        rows.append(("up_tx_%d" % i, 1200 + i * 330, "expense", cat[0], acc[0], 1, "default"))
    rows.append(("up_tx_inc", 880000, "income", cat[0], acc[0], 1, "default"))
    for tid, amt, typ, cid, aid, counted, book in rows:
        cur.execute(
            "INSERT OR REPLACE INTO transactions"
            " (id,amount,type,category_id,note,created_at,updated_at,account_id,is_counted,"
            "liability_id,is_repayment,recorder_name,is_reconciled,book_id)"
            " VALUES (?,?,?,?,'升级测试','2026-11-01T00:00:00Z','2026-11-01T00:00:00Z',?,?,NULL,NULL,NULL,0,?)",
            (tid, amt, typ, cid, aid, counted, book))
    con.commit()
    print("  已灌 %d 笔交易" % len(rows))
    con.close()


def main():
    print("=== 1. 装 build 27（1.0.16），建真实老库 ===")
    sh("xcrun", "simctl", "uninstall", SIM, BUNDLE)
    r = sh("xcrun", "simctl", "install", SIM, APP27)
    if r.returncode != 0:
        print("  装 build 27 失败:", r.stderr[:300])
        return 2
    if not launch_and_watch("build27", wait=14):
        print("  build 27 自己就崩了 —— 不是升级路径的问题")
        return 3

    path = db_path()
    con = sqlite3.connect(path)
    ids = [r0[0] for r0 in con.execute(
        "SELECT identifier FROM grdb_migrations ORDER BY rowid")]
    print("  build 27 的迁移记录:", ",".join(ids))
    tables = [r0[0] for r0 in con.execute(
        "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")]
    print("  表数:", len(tables))
    con.close()

    print("=== 2. 灌真实交易数据 ===")
    seed_transactions()

    print("=== 3. 用 build 28 覆盖安装（模拟 App Store 更新）===")
    sh("xcrun", "simctl", "terminate", SIM, BUNDLE)
    time.sleep(1)
    r = sh("xcrun", "simctl", "install", SIM, APP28)
    print("  覆盖安装:", "成功" if r.returncode == 0 else "失败 " + r.stderr[:200])

    print("=== 4. 启动 build 28（触发 v18~v21 迁移）===")
    alive = launch_and_watch("build28", wait=16)

    if not alive:
        print(">>> ❌ 复现成功：真实升级路径崩溃")
        # 抓崩溃日志
        for p in sh("bash", "-lc",
                    "ls -t ~/Library/Logs/DiagnosticReports/ColorFuLedger*.ips 2>/dev/null | head -2"
                    ).stdout.split():
            print("  崩溃日志:", p)
        return 1

    con = sqlite3.connect(db_path())
    ids = [r0[0] for r0 in con.execute(
        "SELECT identifier FROM grdb_migrations ORDER BY rowid")]
    print("  build 28 迁移记录末尾:", ",".join(ids[-5:]))
    n = con.execute("SELECT COUNT(*) FROM transactions").fetchone()[0]
    print("  交易数:", n)
    con.close()
    print(">>> 没崩。升级路径不复现。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
