import json
import os
import subprocess

env = dict(os.environ)
env["PATH"] = "/Users/mac/.blitz/bin:" + env.get("PATH", "")
env["ASC_TIMEOUT"] = "120s"
APP = "6832234671"


def sh(args, timeout=180):
    r = subprocess.run(args, capture_output=True, text=True, env=env, timeout=timeout)
    return r.stdout.strip(), r.stderr.strip(), r.returncode


jwt = sh(["asc", "auth", "token", "--confirm"])[0]


def api(path, method="GET", data=None):
    cmd = ["curl", "-s", "-X", method, path, "-H", "Authorization: Bearer " + jwt]
    if data:
        cmd += ["-H", "Content-Type: application/json", "--data", json.dumps(data)]
    r = subprocess.run(cmd, capture_output=True, text=True, env=env)
    try:
        return json.loads(r.stdout)
    except Exception:
        return {"_raw": r.stdout[:300]}


SUBS_URL = ("https://api.appstoreconnect.apple.com/v1/reviewSubmissions"
            "?filter%5Bapp%5D=" + APP + "&limit=20")

subs = api(SUBS_URL).get("data", [])
print("submission 总数:", len(subs))

empty = []
for it in subs:
    sid = it["id"]
    a = it.get("attributes", {})
    items = api("https://api.appstoreconnect.apple.com/v1/reviewSubmissions/%s/items" % sid).get("data", [])
    state = a.get("state")
    print("  %s | state=%-18s | items=%d" % (sid[:8], state, len(items)))
    if not items and state in ("READY_FOR_REVIEW", "PREPARE_FOR_SUBMISSION"):
        empty.append(sid)

print()
print("空壳（待删）:", [s[:8] for s in empty])
for sid in empty:
    out, err, rc = sh(["curl", "-s", "-o", "/dev/null", "-w", "%{http_code}", "-X", "DELETE",
                        "https://api.appstoreconnect.apple.com/v1/reviewSubmissions/" + sid,
                        "-H", "Authorization: Bearer " + jwt])
    print("  DELETE %s -> HTTP %s" % (sid[:8], out))

print()
print("=== 删除后 ===")
subs2 = api(SUBS_URL).get("data", [])
print("  剩余 submission:", len(subs2))
for it in subs2:
    print("   ", it["id"][:8], it.get("attributes", {}).get("state"))
