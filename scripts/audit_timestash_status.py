import json
import os
import subprocess

env = dict(os.environ)
env["PATH"] = "/Users/mac/.blitz/bin:" + env.get("PATH", "")
env["ASC_TIMEOUT"] = "120s"
APP = "6832234671"
VID = "46a2877b-8ab7-4884-8b21-cfc4583ad3a9"


def api(path):
    jwt = subprocess.run(["asc", "auth", "token", "--confirm"], capture_output=True,
                         text=True, env=env).stdout.strip()
    r = subprocess.run(["curl", "-s", path, "-H", "Authorization: Bearer " + jwt],
                       capture_output=True, text=True, env=env)
    try:
        return json.loads(r.stdout)
    except Exception:
        return {"_raw": r.stdout[:300]}


def items(d):
    if isinstance(d, dict):
        data = d.get("data", []) or []
        if isinstance(data, dict):
            return [data]
        return data
    return []


print("=== 1.0 挂的 build ===")
d = api("https://api.appstoreconnect.apple.com/v1/appStoreVersions/%s/build" % VID)
for it in items(d):
    a = it.get("attributes", {})
    print("  build %s | %s | 上传 %s | id %s"
          % (a.get("version"), a.get("processingState"), a.get("uploadedDate"), it.get("id")))

print()
print("=== 版本层 What's New（48 locale 有多少填了）===")
d = api("https://api.appstoreconnect.apple.com/v1/appStoreVersions/%s/appStoreVersionLocalizations?limit=60" % VID)
locs = items(d)
have = [i["attributes"].get("locale") for i in locs if (i["attributes"].get("whatsNew") or "").strip()]
print("  版本层 locale 总数: %d | 有 What's New: %d" % (len(locs), len(have)))
missing = [i["attributes"].get("locale") for i in locs if not (i["attributes"].get("whatsNew") or "").strip()]
print("  缺:", missing[:10])

print()
print("=== app-info 层（商店名/副标题/隐私链接）===")
ai = api("https://api.appstoreconnect.apple.com/v1/apps/%s/appInfos" % APP)
for it in items(ai):
    aid = it["id"]
    locs2 = api("https://api.appstoreconnect.apple.com/v1/appInfos/%s/appInfoLocalizations?limit=60" % aid)
    ls = items(locs2)
    noName = [x["attributes"].get("locale") for x in ls if not (x["attributes"].get("name") or "").strip()]
    noPP = [x["attributes"].get("locale") for x in ls if not (x["attributes"].get("privacyPolicyUrl") or "").strip()]
    noSub = [x["attributes"].get("locale") for x in ls if not (x["attributes"].get("subtitle") or "").strip()]
    print("  app-info locale 总数: %d" % len(ls))
    print("    缺 name: %d %s" % (len(noName), noName[:6]))
    print("    缺 subtitle: %d %s" % (len(noSub), noSub[:6]))
    print("    缺 privacyPolicyUrl: %d %s" % (len(noPP), noPP[:6]))

print()
print("=== 截图统计（抽样 6 个 locale）===")
locs3 = items(api("https://api.appstoreconnect.apple.com/v1/appStoreVersions/%s/appStoreVersionLocalizations?limit=60" % VID))
sample = [locs3[i] for i in (0, 5, 12, 24, 36, 47) if i < len(locs3)]
for l in sample:
    lid = l["id"]
    loc = l["attributes"].get("locale")
    out = subprocess.run(["asc", "screenshots", "list", "--version-localization", lid, "--output", "json"],
                         capture_output=True, text=True, env=env).stdout
    try:
        j = json.loads(out)
        n = sum(len(s.get("screenshots", []) or []) for s in j.get("sets", []))
    except Exception:
        n = -1
    print("  %-10s %d 张" % (loc, n))
