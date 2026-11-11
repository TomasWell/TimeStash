import json
import os
import subprocess

env = dict(os.environ)
env["PATH"] = "/Users/mac/.blitz/bin:" + env.get("PATH", "")
VID = "a465c086-5b5d-4c52-8dbc-98a7f585f8ca"

out = subprocess.run(["asc", "localizations", "list", "--version", VID, "--output", "json"],
                     capture_output=True, text=True, env=env).stdout
items = json.loads(out).get("data", [])
have = [i["attributes"].get("locale") for i in items if (i["attributes"].get("whatsNew") or "").strip()]
print("locale 数:", len(items), "| 已有 What's New:", len(have))
missing = [i["attributes"].get("locale") for i in items
           if not (i["attributes"].get("whatsNew") or "").strip()]
print("还差:", len(missing), missing[:10])

# 抽查已写入的译文质量
for i in items:
    loc = i["attributes"].get("locale")
    if loc in ("zh-Hans", "en", "de", "ja", "fr"):
        w = i["attributes"].get("whatsNew") or ""
        print("  [%s] %s" % (loc, w[:110]))
