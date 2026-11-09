#!/usr/bin/env python3
"""造一个「像 1.0.16 真实用户」的 v17 老库，然后让 build 28 去迁移。

为什么不能只靠空库：v18 迁移的反推逻辑
    UPDATE accounts SET opening_balance = balance - COALESCE(SUM(...), 0)
在空表上恒等于 balance - 0，走不到任何边界；
只有真实数据（多账户、跨账本 book_id、负债交易、is_counted=0 的排除项）才会踩到。

步骤：
  1. 把当前库退回 v17（撤销 v18~v21 的结构）
  2. 灌入真实形态的数据
  3. 启动 build 28 → 迁移 v18~v21 → 看崩不崩
"""
import os
import sqlite3
import subprocess
import sys
import time

SIM = "E844988F-921E-4F5A-A84F-CB945112AAE0"
BUNDLE = "com.freeledger.app"


def db_path():
    out = subprocess.run(
        ["xcrun", "simctl", "get_app_container", SIM, BUNDLE, "data"],
        capture_output=True, text=True, check=True).stdout.strip()
    return os.path.join(out, "Library", "Application Support", "freeledger.sqlite")


def _has_column(con, table, column):
    return con.execute(
        "SELECT COUNT(*) FROM pragma_table_info(?) WHERE name = ?",
        (table, column)).fetchone()[0] > 0


def downgrade_to_v17(path):
    # 可重复执行：已经退过一次再退不会炸
    con = sqlite3.connect(path)
    con.execute("PRAGMA foreign_keys=OFF")
    if _has_column(con, "accounts", "opening_balance"):
        con.execute("ALTER TABLE accounts DROP COLUMN opening_balance")
    con.execute("DROP INDEX IF EXISTS idx_transactions_payee")
    if _has_column(con, "transactions", "payee"):
        con.execute("ALTER TABLE transactions DROP COLUMN payee")
    con.execute("DROP TABLE IF EXISTS merchant_category_mappings")
    con.execute("DELETE FROM grdb_migrations WHERE identifier IN ('v18','v19','v20','v21')")
    con.commit()
    con.close()


def seed(path):
    # 灌真实形态的数据：多账户、多账本、负债交易、被排除的交易
    con = sqlite3.connect(path)
    cur = con.cursor()

    cats = [
        ("cat_food", "food", "fork.knife", "#FF9500", "expense"),
        ("cat_salary", "salary", "bag", "#34C759", "income"),
        ("cat_house", "house", "house", "#007AFF", "expense"),
        ("cat_debt", "debt", "creditcard", "#FF3B30", "expense"),
    ]
    for cid, key, icon, color, typ in cats:
        cur.execute(
            "INSERT OR REPLACE INTO categories"
            " (id,name_key,icon_name,color_hex,type,sort_order,usage_count,is_custom,is_active,parent_id)"
            " VALUES (?,?,?,?,?,0,0,0,1,NULL)", (cid, key, icon, color, typ))

    accounts = [
        ("acc_cash", "现金", "cash", 120000, "default"),
        ("acc_bank", "银行卡", "bank", 3500000, "default"),
        ("acc_home", "家庭账本现金", "cash", 80000, "book_home"),
    ]
    for aid, name, typ, bal, book in accounts:
        cur.execute(
            "INSERT OR REPLACE INTO accounts"
            " (id,name,type,balance,icon_name,color_hex,sort_order,is_active,created_at,updated_at,name_key,is_custom,book_id)"
            " VALUES (?,?,?,?,?,?,0,1,'2026-01-01T00:00:00Z','2026-01-01T00:00:00Z','',0,?)",
            (aid, name, typ, bal, "creditcard", "#000000", book))

    if cur.execute("SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='liabilities'").fetchone()[0]:
        cur.execute(
            "INSERT OR REPLACE INTO liabilities"
            " (id,name,type,credit_limit,billing_day,repayment_day,category_id,is_active,created_at,updated_at)"
            " VALUES ('liab_1','花呗','credit_line',500000,1,10,'cat_debt',1,"
            "'2026-01-01T00:00:00Z','2026-01-01T00:00:00Z')")

    if cur.execute("SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='books'").fetchone()[0]:
        cur.execute(
            "INSERT OR REPLACE INTO books"
            " (id,name,icon_name,color_hex,sort_order,is_default,created_at,updated_at)"
            " VALUES ('book_home','家庭账本','book.closed','#4A90D9',1,0,"
            "'2026-01-01T00:00:00Z','2026-01-01T00:00:00Z')")

    txs = [
        ("t1", 500000, "income", "cat_salary", "acc_bank", 1, None, "default"),
        ("t2", 3500, "expense", "cat_food", "acc_bank", 1, None, "default"),
        ("t3", 12000, "expense", "cat_house", "acc_cash", 1, None, "default"),
        ("t4", 8800, "expense", "cat_food", "acc_cash", 0, None, "default"),
        ("t5", 6600, "expense", "cat_debt", "acc_bank", 1, "liab_1", "default"),
        ("t6", 4300, "expense", "cat_food", "acc_home", 1, None, "book_home"),
        ("t7", 90000, "income", "cat_salary", "acc_home", 1, None, "book_home"),
    ]
    for tid, amt, typ, cat, acc, counted, liab, book in txs:
        cur.execute(
            "INSERT OR REPLACE INTO transactions"
            " (id,amount,type,category_id,note,created_at,updated_at,account_id,is_counted,"
            "liability_id,is_repayment,recorder_name,is_reconciled,book_id)"
            " VALUES (?,?,?,?,'','2026-10-01T00:00:00Z','2026-10-01T00:00:00Z',?,?,?,NULL,NULL,0,?)",
            (tid, amt, typ, cat, acc, counted, liab, book))

    con.commit()
    n_acc = cur.execute("SELECT COUNT(*) FROM accounts").fetchone()[0]
    n_tx = cur.execute("SELECT COUNT(*) FROM transactions").fetchone()[0]
    con.close()
    print("  账户 %d 条 / 交易 %d 条" % (n_acc, n_tx))


def main():
    path = db_path()
    print("DB:", path)
    subprocess.run(["xcrun", "simctl", "terminate", SIM, BUNDLE], capture_output=True)
    downgrade_to_v17(path)
    print("已退回 v17")
    seed(path)
    print("已灌入真实形态数据")

    p = subprocess.run(["xcrun", "simctl", "launch", SIM, BUNDLE],
                       capture_output=True, text=True)
    print("launch:", (p.stdout or p.stderr).strip())

    time.sleep(10)
    r = subprocess.run(["xcrun", "simctl", "spawn", SIM, "launchctl", "list"],
                       capture_output=True, text=True).stdout
    alive = "freeledger" in r.lower()
    print("进程还活着:", alive)
    if not alive:
        print(">>> 崩了 —— 这就是线上崩溃的复现")
    else:
        con = sqlite3.connect(path)
        ids = [row[0] for row in con.execute(
            "SELECT identifier FROM grdb_migrations ORDER BY identifier")]
        con.close()
        print("迁移记录末尾:", ",".join(ids[-6:]))
    return 0 if alive else 1


if __name__ == "__main__":
    sys.exit(main())
