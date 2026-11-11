import json
import os
import subprocess
import time

env = dict(os.environ)
env["PATH"] = "/Users/mac/.blitz/bin:" + env.get("PATH", "")
env["ASC_TIMEOUT"] = "120s"

VID = "a465c086-5b5d-4c52-8dbc-98a7f585f8ca"
KEY = "whatsnew_120"


def read_ko():
    p = "/tmp/whatsnew_120_i18n/ko.lproj/Localizable.strings"
    with open(p, encoding="utf-8") as f:
        for line in f:
            s = line.strip()
            if s.startswith('"%s"' % KEY):
                v = s.split("=", 1)[1].strip()
                if v.endswith(";"):
                    v = v[:-1]
                return v.strip().strip('"')
    return None


def count_have():
    out = subprocess.run(["asc", "localizations", "list", "--version", VID, "--output", "json"],
                         capture_output=True, text=True, env=env).stdout
    items = json.loads(out).get("data", [])
    have = [i["attributes"].get("locale") for i in items
            if (i["attributes"].get("whatsNew") or "").strip()]
    missing = [i["attributes"].get("locale") for i in items
               if not (i["attributes"].get("whatsNew") or "").strip()]
    return have, missing


ko = read_ko()
print("韩语译文长度:", len(ko or ""))

for attempt in range(1, 5):
    have, missing = count_have()
    print("第%d次检查: 已有 %d / %d, 还差 %s" % (attempt, len(have), len(have) + len(missing), missing))
    if not missing:
        print("✅ 全部 locale 都有 What's New")
        break
    if "ko" in missing and ko:
        r = subprocess.run(["asc", "localizations", "update", "--version", VID,
                            "--locale", "ko", "--whats-new", ko],
                           capture_output=True, text=True, env=env)
        print("  ko 写入:", "成功" if (r.returncode == 0 and not r.stderr.strip())
              else ("失败 " + (r.stderr or r.stdout)[:150]))
    time.sleep(5)

have, missing = count_have()
print()
print("最终: %d / %d，缺: %s" % (len(have), len(have) + len(missing), missing))
