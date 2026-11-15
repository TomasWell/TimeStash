import json
import os
import subprocess

env = dict(os.environ)
env["PATH"] = "/Users/mac/.blitz/bin:" + env.get("PATH", "")
env["ASC_TIMEOUT"] = "120s"

APPS = [
    ("私密记账", "6759187331"),
    ("时间收纳箱", "6832234671"),
    ("萌宠手册", "6825799483"),
    ("卡点通勤", "6821559872"),
]

TS_VERSION = "46a2877b-8ab7-4884-8b21-cfc4583ad3a9"


def asc(args, timeout=120):
    """跑 asc，返回 (parsed, stderr)。parsed 为 None 表示解析失败。"""
    try:
        r = subprocess.run(["asc"] + args, capture_output=True, text=True,
                           env=env, timeout=timeout)
    except subprocess.TimeoutExpired:
        return None, "超时"
    try:
        return json.loads(r.stdout), r.stderr.strip()
    except Exception:
        return None, (r.stderr.strip() or r.stdout.strip()[:120])


def data_of(d):
    """ASC 的 data 有时是 list、有时是 dict —— 两种都兼容。"""
    if isinstance(d, dict):
        data = d.get("data")
    elif isinstance(d, list):
        data = d
    else:
        return []
    if isinstance(data, dict):
        return [data]
    if isinstance(data, list):
        return [x for x in data if isinstance(x, dict)]
    return []


def review_line(aid):
    """审核侧状态：优先 asc review status（权威），回退 review history。"""
    d, err = asc(["review", "status", "--app", aid])
    if d:
        v = d.get("version") or {}
        sub = d.get("latestSubmission") or {}
        state = d.get("reviewState") or v.get("state") or "?"
        submitted = sub.get("submittedDate")
        if submitted:
            return "%s（已送审）" % state
        if state in ("READY_FOR_REVIEW", "PREPARE_FOR_SUBMISSION"):
            return "%s（已挂 submission，尚未送审）" % state
        return str(state)

    h, err = asc(["review", "history", "--app", aid])
    items = data_of(h)
    if items:
        at = items[0].get("attributes") or {}
        out = at.get("outcome") or at.get("state") or at.get("versionString")
        if out:
            return str(out)
    return "读不到（%s）" % (err[:60] if err else "无返回")


print("%-12s %-8s %-24s %-24s %s" % ("App", "版本", "appStoreState", "appVersionState", "审核侧"))
print("-" * 104)
for name, aid in APPS:
    d, err = asc(["versions", "list", "--app", aid, "--output", "json"])
    items = data_of(d)
    if not items:
        print("%-12s 读取失败：%s" % (name, (err or "无版本")[:70]))
        continue
    a = items[0].get("attributes") or {}
    print("%-12s %-8s %-24s %-24s %s"
          % (name, a.get("versionString"), a.get("appStoreState"),
             a.get("appVersionState"), review_line(aid)))

print()
print("=== 时间收纳箱：What's New 写入进度 ===")
d, err = asc(["localizations", "list", "--version", TS_VERSION, "--output", "json"])
locs = data_of(d)
if locs:
    have = []
    for i in locs:
        at = i.get("attributes") or {}
        if (at.get("whatsNew") or "").strip():
            have.append(at.get("locale"))
    print("  %d / %d locale 已有 What's New" % (len(have), len(locs)))
    if len(have) < len(locs):
        print("  （首版允许留空 —— ASC 锁着 whatsNew，不阻塞提审）")
else:
    print("  读取失败：%s" % (err or "无返回")[:80])

print()
print("=== 时间收纳箱：隐私问卷发布状态（探针）===")
r = subprocess.run(["python3", "/Users/mac/.hermes/scripts/timestash_privacy_watch.py"],
                   capture_output=True, text=True, env=env, timeout=200)
print("  " + (r.stdout.strip() or "（无输出）"))
print("  PENDING = 隐私问卷还没发布，用户需在 ASC 网页点「发布」")
print("  SUBMITTED / DONE = 已自动提审")
