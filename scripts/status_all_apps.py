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


def asc(args):
    r = subprocess.run(["asc"] + args, capture_output=True, text=True, env=env)
    try:
        return json.loads(r.stdout)
    except Exception:
        return None


print("%-12s %-7s %-26s %-22s %s" % ("App", "版本", "appStoreState", "appVersionState", "审核结果"))
print("-" * 92)
for name, aid in APPS:
    d = asc(["versions", "list", "--app", aid, "--output", "json"])
    if not d:
        print("%-12s 读取失败" % name)
        continue
    items = d.get("data", [])
    if not items:
        print("%-12s 无版本" % name)
        continue
    a = items[0].get("attributes", {})
    # 提审结果
    h = asc(["review", "history", "--app", aid, "--output", "json"])
    outcome = "—"
    if isinstance(h, dict):
        hi = h.get("data", [])
    elif isinstance(h, list):
        hi = h
    else:
        hi = []
    if hi:
        at = hi[0].get("attributes", {}) if isinstance(hi[0], dict) else {}
        outcome = str(at.get("outcome") or at.get("state") or at.get("versionString") or "")
    print("%-12s %-7s %-26s %-22s %s"
          % (name, a.get("versionString"), a.get("appStoreState"), a.get("appVersionState"), outcome))

print()
print("=== 时间收纳箱：What's New 写入进度 ===")
d = asc(["localizations", "list", "--version", "46a2877b-8ab7-4884-8b21-cfc4583ad3a9", "--output", "json"])
if d:
    locs = d.get("data", [])
    have = [i["attributes"].get("locale") for i in locs if (i["attributes"].get("whatsNew") or "").strip()]
    print("  %d / %d locale 已有 What's New" % (len(have), len(locs)))
