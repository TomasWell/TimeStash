import json
import os
import subprocess
import sys

env = dict(os.environ)
env["PATH"] = "/Users/mac/.blitz/bin:" + env.get("PATH", "")
env["ASC_TIMEOUT"] = "120s"
APP = "6832234671"
VID = "46a2877b-8ab7-4884-8b21-cfc4583ad3a9"

SUBS_URL = ("https://api.appstoreconnect.apple.com/v1/reviewSubmissions"
            "?filter%5Bapp%5D=" + APP + "&limit=20")


def sh(args, timeout=200):
    r = subprocess.run(args, capture_output=True, text=True, env=env, timeout=timeout)
    return r.stdout.strip(), r.stderr.strip(), r.returncode


jwt = sh(["asc", "auth", "token", "--confirm"])[0]


def api(path, method="GET"):
    r = subprocess.run(["curl", "-s", "-X", method, path,
                        "-H", "Authorization: Bearer " + jwt],
                       capture_output=True, text=True, env=env)
    try:
        return json.loads(r.stdout)
    except Exception:
        return {"_raw": r.stdout[:300]}


subs = api(SUBS_URL).get("data", [])
print("submission 总数:", len(subs))

added_to = None
last_err = ""
for it in subs:
    sid = it["id"]
    items = api("https://api.appstoreconnect.apple.com/v1/reviewSubmissions/%s/items" % sid).get("data", [])
    if items:
        print("  %s 已有 items=%d → 跳过" % (sid[:8], len(items)))
        added_to = sid
        continue
    out, err, rc = sh(["asc", "review", "items-add", "--submission", sid,
                        "--item-type", "appStoreVersions", "--item-id", VID,
                        "--output", "json"])
    if rc == 0 and not err.strip():
        print("  ✅ %s 挂上版本成功" % sid[:8])
        added_to = sid
        break
    last_err = err or out
    print("  ❌ %s -> %s" % (sid[:8], last_err.split("\n")[0][:140]))

if not added_to:
    print()
    print("全部失败。最后一个完整错误：")
    print(last_err[:900])
    sys.exit(2)

print()
print("=== 提交 %s ===" % added_to[:8])
out, err, rc = sh(["asc", "review", "submissions-submit", "--id", added_to,
                   "--confirm", "--output", "json"])
if rc != 0:
    print("提交失败:", (err or out)[:600])
    sys.exit(3)
try:
    print("  ", json.loads(out)["data"]["attributes"])
except Exception:
    print("  ", out[:400])

final = api("https://api.appstoreconnect.apple.com/v1/reviewSubmissions/" + added_to)
print("  回读:", json.dumps(final.get("data", {}).get("attributes", {}), ensure_ascii=False))

v = api("https://api.appstoreconnect.apple.com/v1/appStoreVersions/" + VID)
a = v.get("data", {}).get("attributes", {})
print("  版本状态: appStoreState=%s | versionState=%s" % (a.get("appStoreState"), a.get("appStoreState")))
