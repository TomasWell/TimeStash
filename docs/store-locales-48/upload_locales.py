#!/usr/bin/env python3
"""把 translations.json 的 28 个 locale 写进 ASC（两层：appInfo + appStoreVersion）。

用法：
  python3 upload_locales.py --check     # 只读回验证
  python3 upload_locales.py --dry-run   # 演示要写什么
  python3 upload_locales.py --apply     # 真写
"""
import argparse, json, os, subprocess, sys, time, urllib.error, urllib.request

API = "https://api.appstoreconnect.apple.com"
APP_ID = "6832234671"
APPINFO_ID = "b6a56533-3f1b-4cdb-b19b-4c2cb70a400d"
VERSION_ID = "46a2877b-8ab7-4884-8b21-cfc4583ad3a9"
ASC_BIN = os.path.expanduser("~/.blitz/bin/asc")
HERE = os.path.dirname(os.path.abspath(__file__))
ASC_ENV = dict(os.environ, HTTPS_PROXY="http://127.0.0.1:7890",
               HTTP_PROXY="http://127.0.0.1:7890", ASC_TIMEOUT="180s")

def token():
    r = subprocess.run([ASC_BIN, "auth", "token", "--confirm"],
                       capture_output=True, text=True, timeout=120, env=ASC_ENV)
    if r.returncode != 0 or not r.stdout.strip():
        sys.exit(f"auth failed: {r.stderr[:200]}")
    return r.stdout.strip()

def call(method, path, tok, body=None):
    # 每次 call 重新取 token？不：10 分钟有效期，超过就重取
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(f"{API}{path}", data=data, method=method)
    req.add_header("Authorization", f"Bearer {tok}")
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            raw = resp.read().decode()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        return {"_error": e.code, "_detail": e.read().decode()[:400]}
    except Exception as e:
        return {"_error": str(e)[:150]}

class T:  # token 管理：每 8 分钟强制刷新
    def __init__(self): self.t = None; self.ts = 0
    def get(self):
        if not self.t or time.time() - self.ts > 480:
            self.t = token(); self.ts = time.time()
        return self.t

def load_tr():
    return json.load(open(os.path.join(HERE, "merged.json"), encoding="utf-8"))

def list_locales(tok):
    """返回 (appInfoLocs dict, versionLocs dict) —— locale -> id"""
    ai = {}
    d = call("GET", f"/v1/appInfos/{APPINFO_ID}/appInfoLocalizations?limit=200", tok)
    if "_error" in d: sys.exit(f"list appInfoLocs: {d}")
    for l in d["data"]: ai[l["attributes"]["locale"]] = l["id"]
    vs = {}
    d = call("GET", f"/v1/appStoreVersions/{VERSION_ID}/appStoreVersionLocalizations?limit=100", tok)
    if "_error" in d: sys.exit(f"list versionLocs: {d}")
    for l in d["data"]: vs[l["attributes"]["locale"]] = l["id"]
    return ai, vs

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()
    tr = load_tr()
    tm = T()
    tok = tm.get()
    ai, vs = list_locales(tok)
    print(f"现有 appInfo locale {len(ai)} / version locale {len(vs)}；待写 {len(tr)} 个")

    if args.check:
        ai2, vs2 = list_locales(tm.get())
        ok = bad = 0
        for loc, v in tr.items():
            a = ai2.get(loc); b = vs2.get(loc)
            if not a or not b:
                print(f"  ❌ {loc}: appInfo={'✓' if a else '缺'} version={'✓' if b else '缺'}"); bad += 1; continue
            # 抽查 description 是否含该 locale 翻译特征（非英文母版）
            d = call("GET", f"/v1/appStoreVersionLocalizations/{b}", tm.get())
            desc = (d.get("data", {}).get("attributes", {}) or {}).get("description") or ""
            kw = (d.get("data", {}).get("attributes", {}) or {}).get("keywords") or ""
            if desc and desc != tr[loc].get("description", ""):
                print(f"  ⚠️ {loc}: desc 不一致（len {len(desc)} vs {len(tr[loc]['description'])}）")
            else:
                print(f"  ✓ {loc}: desc={len(desc)} kw={kw[:40]}"); ok += 1
        print(f"\n回读验证：{ok} ok / {bad} bad")
        return

    results = {"ok": [], "fail": []}
    for loc, v in sorted(tr.items()):
        # 1) appInfo 层：name + subtitle
        if loc in ai:
            print(f"  [skip-appinfo] {loc} 已存在")
        else:
            body = {"data": {"type": "appInfoLocalizations",
                             "attributes": {"locale": loc, "name": v["name"],
                                            "subtitle": v.get("subtitle", "")},
                             "relationships": {"appInfo": {"data": {"type": "appInfos", "id": APPINFO_ID}}}}}
            if args.apply:
                r = call("POST", "/v1/appInfoLocalizations", tm.get(), body)
                if "_error" in r:
                    print(f"  ❌ appInfo {loc}: {r.get('_error')} {r.get('_detail','')[:150]}")
                    results["fail"].append(("appinfo", loc, str(r.get('_error')))); continue
                print(f"  ✓ appInfo {loc} 建好")
            else:
                print(f"  [dry] appInfo {loc}: name={v['name']!r} sub={v['subtitle']!r}")
        # 2) version 层：desc/keywords/promo
        if loc in vs:
            print(f"  [skip-version] {loc} 已存在")
            results["ok"].append(loc)
            continue
        body = {"data": {"type": "appStoreVersionLocalizations",
                         "attributes": {"locale": loc,
                                        "description": v["description"],
                                        "keywords": v["keywords"],
                                        "promotionalText": v.get("promotionalText", ""),
                                        "marketingUrl": "https://junxf.cn/timestash/",
                                        "supportUrl": "https://junxf.cn/timestash/support.html"},
                         "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": VERSION_ID}}}}}
        if args.apply:
            r = call("POST", "/v1/appStoreVersionLocalizations", tm.get(), body)
            if "_error" in r:
                print(f"  ❌ version {loc}: {r.get('_error')} {r.get('_detail','')[:150]}")
                results["fail"].append(("version", loc, str(r.get('_error')))); continue
            time.sleep(0.5)
            print(f"  ✓ version {loc} 建好（desc {len(v['description'])} 字）")
        else:
            print(f"  [dry] version {loc}: desc {len(v['description'])} 字 kw {v['keywords'][:30]}…")
        if not args.dry_run and args.apply:
            results["ok"].append(loc)
    print(f"\n结果：{len(results['ok'])} ok / {len(results['fail'])} fail")
    if results["fail"]:
        json.dump(results["fail"], open(os.path.join(HERE, "upload_failures.json"), "w"), ensure_ascii=False, indent=1)

if __name__ == "__main__":
    main()
