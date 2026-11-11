import json
import os
import subprocess

env = dict(os.environ)
env["PATH"] = "/Users/mac/.blitz/bin:" + env.get("PATH", "")
env["ASC_TIMEOUT"] = "120s"
APP = "6759187331"
VID = "a465c086-5b5d-4c52-8dbc-98a7f585f8ca"


def api(path):
    jwt = subprocess.run(["asc", "auth", "token", "--confirm"], capture_output=True,
                         text=True, env=env).stdout.strip()
    r = subprocess.run(["curl", "-s", path, "-H", "Authorization: Bearer " + jwt],
                       capture_output=True, text=True, env=env)
    return json.loads(r.stdout)


subs = api("https://api.appstoreconnect.apple.com/v1/reviewSubmissions"
           "?filter%5Bapp%5D=" + APP + "&limit=10").get("data", [])

target = None
for it in subs:
    sid = it["id"]
    state = it["attributes"].get("state")
    items = api("https://api.appstoreconnect.apple.com/v1/reviewSubmissions/%s/items" % sid).get("data", [])
    print("  %s  items=%d  state=%s  submitted=%s"
          % (sid[:8], len(items), state, it["attributes"].get("submittedDate")))
    if len(items) == 1 and state == "READY_FOR_REVIEW":
        target = sid

if not target:
    print("\n没有找到带 1 个 item 且 READY_FOR_REVIEW 的 submission")
    raise SystemExit(1)

print("\n选中:", target)

# 提交
r = subprocess.run(["asc", "review", "submissions-submit", "--id", target, "--confirm",
                    "--output", "json"], capture_output=True, text=True, env=env)
print("提交输出:", r.stdout[:400])
if r.stderr.strip():
    print("stderr:", r.stderr[:300])

# 回读验证
final = api("https://api.appstoreconnect.apple.com/v1/reviewSubmissions/%s" % target)
print("\n回读:", json.dumps(final.get("data", {}).get("attributes", {}), ensure_ascii=False))

v = api("https://api.appstoreconnect.apple.com/v1/appStoreVersions/%s" % VID)
print("版本状态:", json.dumps(v.get("data", {}).get("attributes", {}), ensure_ascii=False)[:260])
