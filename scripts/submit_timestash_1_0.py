import json
import os
import subprocess

env = dict(os.environ)
env["PATH"] = "/Users/mac/.blitz/bin:" + env.get("PATH", "")
env["ASC_TIMEOUT"] = "120s"

APP = "6832234671"
VID = "46a2877b-8ab7-4884-8b21-cfc4583ad3a9"


def sh(args, timeout=300):
    r = subprocess.run(args, capture_output=True, text=True, env=env, timeout=timeout)
    return r.stdout.strip(), r.stderr.strip(), r.returncode


def api(path):
    jwt = sh(["asc", "auth", "token", "--confirm"])[0]
    r = subprocess.run(["curl", "-s", path, "-H", "Authorization: Bearer " + jwt],
                       capture_output=True, text=True, env=env)
    try:
        return json.loads(r.stdout)
    except Exception:
        return {}


# 1. 新建 submission（**必须新建**：空 submission 会让 items-add 报 500）
out, err, rc = sh(["asc", "review", "submissions-create", "--app", APP,
                    "--platform", "IOS", "--output", "json"])
try:
    rs = json.loads(out)["data"]["id"]
except Exception:
    print("建 submission 失败:", out[:200], err[:200])
    raise SystemExit(1)
print("新 submission:", rs)

# 2. 立刻挂版本（一次成功；失败就换一个新建的 submission 重试）
added = False
for attempt in range(3):
    out2, err2, rc2 = sh(["asc", "review", "items-add", "--submission", rs,
                           "--item-type", "appStoreVersions", "--item-id", VID,
                           "--output", "json"])
    if rc2 == 0 and not err2.strip():
        added = True
        print("  挂版本成功（第 %d 次）" % (attempt + 1))
        break
    print("  挂版本失败（第 %d 次）: %s" % (attempt + 1, err2[:150]))
    # 空 submission 会导致 500 → 换一个新建的
    out3, err3, rc3 = sh(["asc", "review", "submissions-create", "--app", APP,
                          "--platform", "IOS", "--output", "json"])
    try:
        rs = json.loads(out3)["data"]["id"]
        print("  换新 submission:", rs)
    except Exception:
        break

if not added:
    print("挂版本最终失败")
    raise SystemExit(1)

# 3. 确认 item 在
items = api("https://api.appstoreconnect.apple.com/v1/reviewSubmissions/%s/items" % rs)
data = items.get("data", []) if isinstance(items, dict) else []
print("  submission 里的 item 数:", len(data))

# 4. 提交
out4, err4, rc4 = sh(["asc", "review", "submissions-submit", "--id", rs,
                       "--confirm", "--output", "json"])
if rc4 != 0:
    print("提交失败:", out4[:300], err4[:300])
    raise SystemExit(1)
try:
    print("  提交结果:", json.loads(out4)["data"]["attributes"])
except Exception:
    print("  提交输出:", out4[:300])

# 5. 回读验证
final = api("https://api.appstoreconnect.apple.com/v1/reviewSubmissions/%s" % rs)
print("  回读:", json.dumps(final.get("data", {}).get("attributes", {}), ensure_ascii=False))

v = api("https://api.appstoreconnect.apple.com/v1/appStoreVersions/%s" % VID)
a = v.get("data", {}).get("attributes", {})
print("  版本状态: %s | %s" % (a.get("appStoreState"), a.get("appVersionState")))
