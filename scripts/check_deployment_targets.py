import json
import os
import re
import subprocess

env = dict(os.environ)
env["PATH"] = "/Users/mac/.blitz/bin:" + env.get("PATH", "")
env["ASC_TIMEOUT"] = "90s"

APPS = {
    "私密记账": "6759187331",
    "萌宠手册": "6825799483",
    "卡点通勤": "6821559872",
}

print("=== 各 App 线上 build 的 minOs ===")
for name, aid in APPS.items():
    r = subprocess.run(["asc", "builds", "list", "--app", aid, "--output", "json"],
                       capture_output=True, text=True, env=env)
    try:
        d = json.loads(r.stdout)
    except Exception:
        print("  %-10s 读取失败: %s" % (name, r.stdout[:80]))
        continue
    items = d.get("data", [])
    if not items:
        print("  %-10s 无 build 数据" % name)
        continue
    a = items[0].get("attributes", {})
    print("  %-10s build %-4s minOs %-8s 状态 %s"
          % (name, a.get("version"), a.get("minOsVersion"), a.get("processingState")))

print()
print("=== TimeStash 的 deploymentTarget ===")
p = "/Users/mac/TimeStash/ios/project.yml"
t = open(p, encoding="utf-8").read()
i = t.find("deploymentTarget")
print(t[i:i+120] if i >= 0 else "没找到")

print()
print("=== 其它 App 本地工程的 deploymentTarget ===")
for name, path in (("TimeStash", "/Users/mac/TimeStash/ios/project.yml"),
                    ("HabitFlow", "/Users/mac/HabitFlow/ios/project.yml"),
                    ("CommutePilot", "/Users/mac/CommutePilot/ios/project.yml"),
                    ("DailyMe", "/Users/mac/DailyMe/ios/project.yml"),
                    ("PawRecord", "/Users/mac/PawRecord/ios/project.yml")):
    if not os.path.exists(path):
        print("  %-13s 工程不在 %s" % (name, path))
        continue
    t = open(path, encoding="utf-8").read()
    m = re.search(r"deploymentTarget:\s*\n\s*iOS:\s*\"([^\"]+)\"", t)
    m2 = re.search(r'IPHONEOS_DEPLOYMENT_TARGET:\s*"?([\d.]+)"?', t)
    print("  %-13s deploymentTarget=%s  IPHONEOS=%s"
          % (name, m.group(1) if m else "?", m2.group(1) if m2 else "?"))
