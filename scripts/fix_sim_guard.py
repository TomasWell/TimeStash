#!/usr/bin/env python3
"""修 sim_guard.py：守护自己的检查绝不能让它自己崩。

2026-11-08 00:48 实测事故：
  `guard_concurrent_repo_writes()` 里 `subprocess.run(["lsof", "+D", path], timeout=25)`
  在机器繁忙时（开发档正在跑 xcodebuild）递归扫仓库目录超时 →
  `subprocess.TimeoutExpired` 没有被捕获 → 整个 sim_guard 抛异常退出 →
  cron 把「模拟器与仓库守门」这一档记成 failed。

守门的职责是保护别的档位，它自己挂掉就等于没人守。而超时这件事本身的
正确处理是「这一项判不出来，跳过」，不是「整个守护崩掉」。

改两处：
  1. lsof 调用包 try/except，超时/异常 → 记一条「判不出来」并继续下一个 App
  2. main() 整体包 try/except，任何未预料的异常都变成一条输出而不是崩溃
"""
import io
import os

PATH = os.path.expanduser('~/.hermes/scripts/sim_guard.py')

OLD_LSOF = '''        # 找出正在写这个目录的进程
        r = subprocess.run(["lsof", "+D", path], capture_output=True, text=True, timeout=25)
        holders = set()
        for line in r.stdout.splitlines()[1:]:'''

NEW_LSOF = '''        # 找出正在写这个目录的进程
        #
        # ⚠️ 2026-11-08 00:48 实测：`lsof +D` 是递归全目录扫，机器繁忙时
        # （开发档正在跑 xcodebuild，仓库里 DerivedData/node_modules 很大）
        # 会超过 25 秒。原代码没捕获 TimeoutExpired → 整个守护抛异常退出
        # → cron 把「模拟器与仓库守门」记成 failed。
        # 这里超时 = 「这一项判不出来」，跳过即可，绝不能让守护自己崩。
        try:
            r = subprocess.run(
                ["lsof", "+D", path],
                capture_output=True,
                text=True,
                timeout=12,
            )
        except subprocess.TimeoutExpired:
            findings.append("- %s: lsof 扫描超时（12s），本次并发写判不出来，跳过" % app)
            continue
        except OSError as exc:
            findings.append("- %s: lsof 调用失败（%s），本次并发写判不出来，跳过" % (app, exc))
            continue
        holders = set()
        for line in r.stdout.splitlines()[1:]:'''

OLD_MAIN = '''    out = []
    out += guard_high_load()
    out += heal_global_lock()
    out += guard_simulator_uniqueness()
    out += guard_crash_loop(a.window_min, a.threshold, a.dry_run)
    out += guard_dev_slot_timeout(a.max_slot_min)
    out += guard_concurrent_repo_writes()

    if out:
        print("\\n".join(out))
    return 0'''

NEW_MAIN = '''    out = []
    # 每个检查单独包一层：任何一项抛异常都不能带倒整个守护
    # （2026-11-08 00:48 实测：并发写检查里的 lsof 超时就把这一档打成 failed）。
    checks = (
        ("高负载", lambda: guard_high_load()),
        ("全局锁自愈", lambda: heal_global_lock()),
        ("模拟器唯一性", lambda: guard_simulator_uniqueness()),
        ("崩溃循环", lambda: guard_crash_loop(a.window_min, a.threshold, a.dry_run)),
        ("开发档超时", lambda: guard_dev_slot_timeout(a.max_slot_min)),
        ("仓库并发写", lambda: guard_concurrent_repo_writes()),
    )
    for name, fn in checks:
        try:
            out += fn()
        except Exception as exc:  # noqa: BLE001 - 守护不能因单项异常而崩
            msg = "- %s 检查异常（守护继续）: %s: %s" % (name, type(exc).__name__, exc)
            out.append(msg)
            try:
                with open(GUARD_LOG, "a", encoding="utf-8") as f:
                    f.write("\\n## %s %s 检查异常\\n- %s: %s\\n"
                            % (time.strftime("%Y-%m-%d %H:%M:%S"), name,
                               type(exc).__name__, exc))
            except Exception:
                pass

    if out:
        print("\\n".join(out))
    return 0'''

with io.open(PATH, encoding='utf-8') as f:
    s = f.read()

if 'lsof 扫描超时（12s）' in s:
    print('已打过补丁，跳过')
else:
    assert OLD_LSOF in s, '找不到 lsof 调用锚点'
    assert OLD_MAIN in s, '找不到 main 锚点'
    s = s.replace(OLD_LSOF, NEW_LSOF)
    s = s.replace(OLD_MAIN, NEW_MAIN)
    with io.open(PATH, 'w', encoding='utf-8') as f:
        f.write(s)
    print('已修补 sim_guard.py')
