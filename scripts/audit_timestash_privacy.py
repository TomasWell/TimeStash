import os
import re
import subprocess

ROOT = "/Users/mac/TimeStash/ios"
SKIP = {"DerivedData", "build", ".build", "SourcePackages", ".git"}

# 1) 有没有网络请求
NET = re.compile(r"URLSession|URLRequest|dataTask|uploadTask|Alamofire|https?://|NSURLConnection|CFNetwork")
# 2) 有没有第三方 SDK / 追踪
SDK = re.compile(r"Firebase|Analytics|Sentry|Crashlytics|Amplitude|Mixpanel|Adjust|AppsFlyer|AdMob|Facebook|Twitter|GoogleMobileAds")
# 3) 有没有账号 / 登录
ACCT = re.compile(r"SignInWithApple|AuthenticationServices|ASAuthorization|login|signIn|userAccount")
# 4) 有没有 iCloud / CloudKit
CLOUD = re.compile(r"CloudKit|CKContainer|NSUbiquitousKeyValueStore|iCloud")
# 5) App Group（App 与 Widget 之间共享 —— 不是「收集数据」，但问卷要如实说明）
GROUP = re.compile(r"containerURL|forSecurityApplicationGroupIdentifier")

findings = {k: [] for k in ("NET", "SDK", "ACCT", "CLOUD", "GROUP")}

for dirpath, dirnames, filenames in os.walk(ROOT):
    dirnames[:] = [d for d in dirnames if d not in SKIP]
    for fn in filenames:
        if not fn.endswith(".swift"):
            continue
        p = os.path.join(dirpath, fn)
        rel = os.path.relpath(p, ROOT)
        if "/Tests/" in "/" + rel or "/UITests/" in "/" + rel:
            continue
        try:
            lines = open(p, encoding="utf-8").read().split("\n")
        except Exception:
            continue
        for i, line in enumerate(lines, 1):
            t = line.strip()
            if t.startswith("//") or t.startswith("///") or t.startswith("*"):
                continue
            for key, pat in (("NET", NET), ("SDK", SDK), ("ACCT", ACCT),
                             ("CLOUD", CLOUD), ("GROUP", GROUP)):
                if pat.search(line):
                    findings[key].append("%s:%d  %s" % (rel, i, t[:100]))

for key, label in (("NET", "网络请求"), ("SDK", "第三方 SDK / 追踪"),
                   ("ACCT", "账号 / 登录"), ("CLOUD", "iCloud / CloudKit"),
                   ("GROUP", "App Group（App 与 Widget 共享）")):
    hits = findings[key]
    print("=== %s：%d 处 ===" % (label, len(hits)))
    for h in hits[:8]:
        print("   ", h)
    print()
