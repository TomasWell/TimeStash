#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""TimeStash 1.0 商店页截图：删除旧图 + 逐张上传各 locale 的新图

⚠️ 铁律（全部来自 2026-11-07 HabitFlow / 11-10 DailyMe 的实测教训）：
1. **ASC 截图上传是「追加」不是「覆盖」** —— 同名文件再传一次，商店页就多一张
   重复图。⇒ **必须先删掉该 locale 的旧图，再传新的**。
2. **逐张串行**，绝不并发 —— 并发/批量传会卡死（Python 线程池死锁 / xargs 卡住 /
   一次传多张卡在第 2 张 = Apple 侧限流）。
3. **一次只传一张**（--path 传单个文件，不要传目录）。
4. 失败退避重试 3 轮，间隔 5/10/15 秒。
5. ASC_TIMEOUT=300s（默认值必超时）；成功标志是每张 state=="COMPLETE"。
6. **失败后必须回读再决定要不要重传** —— ASC 的任何「写」操作都不能假定
   「失败 = 没生效」（上传超时时图其实已经传上去了 → 重传 = 造重复图）。
7. 只改 **iPhone 集**（APP_IPHONE_*），**Watch 集必须保留**
   （displayType 不同，删错 = 整个 Watch 版商店页废了）。

用法：
    python3.11 upload_ts_shots.py --plan          # 只列出要做什么（不写）
    python3.11 upload_ts_shots.py --locale de-DE   # 传一个 locale
    python3.11 upload_ts_shots.py --all            # 传全部（逐个 locale 串行）
    python3.11 upload_ts_shots.py --verify         # 回读每个 locale 的张数
"""
import argparse
import hashlib
import json
import os
import subprocess
import sys
import time
import urllib.request

HOME = os.path.expanduser("~")
APP = "6832234671"
VID = "46a2877b-8ab7-4884-8b21-cfc4583ad3a9"
SHOTS = os.path.join(HOME, "TimeStash", "store-assets", "screenshots")
PROGRESS = os.path.join(HOME, "hermes-workspace", "appstore", "scripts", "ts_shot_progress.json")

# ASC 商店页 locale → App 内 lproj 名（拍图目录名就是 lproj 名）
# ⚠️ ASC 的 locale 与 App 的 lproj 不完全一致：ASC 不认裸语言码
#    （no→nb、ur-PK→ur、zh-Hans→zh-Hans…），必须显式映射。
TAG = {
    "en-US": "en", "en-GB": "en", "en-AU": "en", "en-CA": "en",
    "ar-SA": "ar", "bn-BD": "bn", "de-DE": "de", "el": "el", "es-ES": "es",
    "fr-FR": "fr", "gu-IN": "gu", "kn-IN": "kn", "ml-IN": "ml", "mr-IN": "mr",
    "nl-NL": "nl", "no": "nb", "pa-IN": "pa", "pt-BR": "pt-BR", "pt-PT": "pt-PT",
    "sl-SI": "sl", "ta-IN": "ta", "te-IN": "te", "ur-PK": "ur",
    "zh-Hans": "zh-Hans", "zh-Hant": "zh-Hant",
}

ENV = {**os.environ,
       "PATH": os.path.expanduser("~/.blitz/bin") + ":" + os.environ.get("PATH", ""),
       "NO_PROXY": "*", "ASC_TIMEOUT": "300s"}


def token():
    r = subprocess.run(["asc", "auth", "token", "--confirm"], capture_output=True,
                       text=True, env=ENV)
    t = (r.stdout or "").strip()
    if len(t) < 50:
        raise SystemExit("没拿到 token: %s" % (r.stderr or "")[:120])
    return t


def api(path, tok, method="GET", body=None):
    data = json.dumps(body).encode() if body else None
    req = urllib.request.Request(
        "https://api.appstoreconnect.apple.com" + path, data=data, method=method,
        headers={"Authorization": "Bearer " + tok,
                 "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=180) as r:
            return json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        return {"_error": "HTTP %d %s" % (e.code, e.read().decode()[:200])}
    except Exception as e:
        return {"_error": str(e)}


def asc_json(*args):
    r = subprocess.run(["asc", *args, "--output", "json"], capture_output=True,
                       text=True, env=ENV, timeout=300)
    out = (r.stdout or "").strip()
    if not out.startswith(("{", "[")):
        return None
    try:
        return json.loads(out)
    except Exception:
        return None


def locales(tok):
    d = api("/v1/appStoreVersions/%s/appStoreVersionLocalizations?limit=200" % VID, tok)
    return [(x["id"], x["attributes"]["locale"]) for x in d.get("data", [])]


def iphone_shots(tok, loc_id):
    """该 locale 的 iPhone 截图 id 列表（**不含 Watch 集**）。"""
    sets = api("/v1/appStoreVersionLocalizations/%s/appScreenshotSets?limit=20" % loc_id, tok)
    out = []
    for s in sets.get("data", []):
        dt = (s.get("attributes") or {}).get("screenshotDisplayType") or ""
        if not dt.startswith("APP_IPHONE"):
            continue                      # ⚠️ Watch 集必须保留
        sh = api("/v1/appScreenshotSets/%s/appScreenshots?limit=100" % s["id"], tok)
        for x in sh.get("data", []):
            out.append((x["id"], (x.get("attributes") or {}).get("fileName") or ""))
    return out


def del_shot(tok, sid):
    r = subprocess.run(["asc", "screenshots", "delete", "--id", sid, "--confirm"],
                       capture_output=True, text=True, env=ENV, timeout=180)
    return r.returncode == 0, (r.stdout or r.stderr or "")[:160]


def upload_one(tok, loc_id, path, fname, before_ids):
    """传一张。返回 (ok, state, detail)

    ⚠️⚠️ 2026-11-16 P0 修正一个**假绿**：
    原来的实现是「回读发现同名文件存在 → 判成功（ALREADY_THERE）」。
    但 ASC 的截图是**追加**语义 —— 同名文件**早就存在**（旧的那套中文图），
    上传新图后同名会变成两张，而回读「有没有同名」根本区分不了
    「新的传上去了」和「旧的还在」→ **每次都误判成成功 → 一张新图都没传**。
    ⇒ 正确判据 = **回读时出现了 before_ids 之外的新 id**，或张数变多。
    """
    for attempt, wait in enumerate((0, 5, 10), 1):
        if wait:
            time.sleep(wait)
        r = subprocess.run(
            ["asc", "screenshots", "upload", "--version-localization", loc_id,
             "--path", path, "--device-type", "APP_IPHONE_67"],
            capture_output=True, text=True, env=ENV, timeout=400)
        out = (r.stdout or "") + (r.stderr or "")
        if "COMPLETE" in out:
            # ⚠️ 命令返回 COMPLETE 也要回读确认（ASC 写操作不能假定成功=生效）
            cur = iphone_shots(tok, lid) if False else iphone_shots(tok, loc_id)
            new_ids = {i for i, _ in cur} - before_ids
            if new_ids:
                return True, "COMPLETE", "回读确认新增 %d 张" % len(new_ids)
            if len(cur) > len(before_ids):
                return True, "COMPLETE", "张数 %d→%d" % (len(before_ids), len(cur))
            return False, "NO_NEW_ASSET", "命令说 COMPLETE 但回读无新增"
        # ⚠️ 失败/超时不等于没传上去 → 回读确认「有没有新增 id」
        cur = iphone_shots(tok, loc_id)
        new_ids = {i for i, _ in cur} - before_ids
        if new_ids:
            return True, "ALREADY_UPLOADED", "回读发现新增 %d 张（未重复上传）" % len(new_ids)
        if len(cur) > len(before_ids):
            return True, "ALREADY_UPLOADED", "回读张数 %d→%d" % (len(before_ids), len(cur))
    return False, "FAILED", out[:200]


def md5(path):
    h = hashlib.md5()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def already_matching(tok, lid, loc, d, files):
    """该 locale 的 ASC 截图是否已经与本地完全一致（10/10 checksum 相同）。

    ⚠️ 2026-11-16 P0 加这条的理由：脚本自报的 "uploaded 10/10" **不可信** ——
    实测 da / el 两个 locale 脚本报「上传 10/10 全绿」，独立回读却是**旧图**
    （checksum 与本地全不相同）→ 又一处假绿。
    ⇒ 传之前先独立比对「ASC 上每张图的 checksum vs 本地文件的 md5」，
      已经一致的**直接跳过**，不浪费配额重传。
    """
    asc = {}
    sets = api("/v1/appStoreVersionLocalizations/%s/appScreenshotSets?limit=20" % lid, tok)
    for st in sets.get("data", []):
        dt = (st.get("attributes") or {}).get("screenshotDisplayType") or ""
        if not dt.startswith("APP_IPHONE"):
            continue
        for x in api("/v1/appScreenshotSets/%s/appScreenshots?limit=100" % st["id"], tok).get("data", []):
            a = x.get("attributes") or {}
            asc[a.get("fileName")] = a.get("sourceFileChecksum")
    if len(asc) != len(files):
        return False, len(asc)
    match = sum(1 for f in files if asc.get(f) and asc[f].lower() == md5(os.path.join(d, f)))
    return match == len(files), match


def local_dir_for(asc_loc):
    tag = TAG.get(asc_loc, asc_loc)
    d = os.path.join(SHOTS, tag)
    return d if os.path.isdir(d) else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--locale")
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--plan", action="store_true")
    ap.add_argument("--verify", action="store_true")
    ap.add_argument("--keep", action="store_true", help="不删旧图（危险：会产生重复图）")
    args = ap.parse_args()

    tok = token()
    locs = locales(tok)
    print("ASC locale 数: %d" % len(locs))

    if args.verify:
        # ⚠️⚠️ 2026-11-16 P0：原来的 --verify **只比数量**，漏掉了真正的问题。
        #   实测 fi=8/hr=9/hu=9 时数量不等，确实被抓到；但「ASC 10 张 + 本地 10 张」
        #   **数量相等却内容是旧图**这种情况完全抓不到 → 正是 da/el 假绿的漏网处。
        #   ⇒ 现在逐张比对 **checksum（ASC）vs md5（本地）**。
        bad = 0
        cs_owner = {}
        detail = []
        for lid, loc in locs:
            sh = iphone_shots(tok, lid)
            d = local_dir_for(loc)
            files = sorted(f for f in os.listdir(d) if f.endswith(".png")) if d else []
            n_local = len(files)
            asc_cs = {}
            for sid, fname in sh:
                # iphone_shots 只回 (id, fileName)；这里再取一次 checksum
                pass
            sets = api("/v1/appStoreVersionLocalizations/%s/appScreenshotSets?limit=20" % lid, tok)
            for st_ in sets.get("data", []):
                dt = (st_.get("attributes") or {}).get("screenshotDisplayType") or ""
                if not dt.startswith("APP_IPHONE"):
                    continue
                for x in api("/v1/appScreenshotSets/%s/appScreenshots?limit=100" % st_["id"], tok).get("data", []):
                    a = x.get("attributes") or {}
                    cs = (a.get("sourceFileChecksum") or "").lower()
                    asc_cs[a.get("fileName")] = cs
                    if cs:
                        cs_owner.setdefault(cs, set()).add(loc)
            match = sum(1 for f in files
                        if asc_cs.get(f) and asc_cs[f] == md5(os.path.join(d, f)))
            ok_loc = (n_local >= 10 and len(sh) == n_local and match == n_local)
            if not ok_loc:
                bad += 1
            detail.append((ok_loc, loc, len(sh), n_local, match))
            print("  %s %-8s ASC %2d 张 / 本地 %2d 张 / checksum 一致 %2d/%d"
                  % ("✅" if ok_loc else "⛔", loc, len(sh), n_local, match, n_local))
        shared = {c: v for c, v in cs_owner.items() if len(v) > 1}
        print("\n== 汇总 ==")
        print("异常 locale 数: %d / %d" % (bad, len(locs)))
        print("跨 locale 共用的 checksum 数: %d" % len(shared))
        for c, v in sorted(shared.items(), key=lambda kv: -len(kv[1]))[:10]:
            print("   %s -> %d 个 locale: %s" % (c[:10], len(v), " ".join(sorted(v))))
        if bad == 0 and not shared:
            print("\n✅ 全部 locale 的截图都与本地一致，且没有任何跨 locale 复用。")
        else:
            print("\n⛔ 仍未达标 —— 上面标 ⛔ 的 locale 需要重传；共用 checksum 的 locale 说明图没换成功。")
        return

    def has_local(loc):
        d = local_dir_for(loc)
        # ⚠️ 必须 == 10 张（本地拍完）—— 原来 >= 5 会把「拍到一半」的 locale
        # 也当成已拍好 → 传上去的张数不足 → 商店页少图（实测 fi 8 张 / hr 9 张）。
        return bool(d) and len([f for f in os.listdir(d) if f.endswith(".png")]) >= 10

    if args.locale:
        targets = [(lid, loc) for lid, loc in locs if loc == args.locale]
    elif args.all:
        # ⚠️ 优先处理「本地已经拍好」的 locale（拍摄还在后台跑）。
        #    原来无条件处理全部 48 个 → 遇到还没拍的 locale 会白跑一轮
        #    （删图 + 上传旧图），白花配额还把顺序打乱。
        targets = [(lid, loc) for lid, loc in locs if has_local(loc)]
        pending = [(lid, loc) for lid, loc in locs if not has_local(loc)]
        if pending:
            print("本地还没拍好的 locale（跳过，等拍完再跑）：%s" %
                  " ".join(loc for _, loc in pending))
    else:
        targets = [(lid, loc) for lid, loc in locs if has_local(loc)]

    if args.plan:
        for lid, loc in targets:
            d = local_dir_for(loc)
            files = sorted(f for f in os.listdir(d) if f.endswith(".png")) if d else []
            cur = iphone_shots(tok, lid)
            print("  %-8s 本地 %2d 张 (dir=%s)  ASC 现存 %2d 张 → 将删 %d 传 %d" % (
                loc, len(files), os.path.basename(d) if d else "缺目录",
                len(cur), len(cur), len(files)))
        return

    progress = {}
    if os.path.exists(PROGRESS):
        progress = json.load(open(PROGRESS))

    for lid, loc in targets:
        d = local_dir_for(loc)
        if not d:
            print("  ⛔ %-8s 本地目录不存在（跳��）" % loc)
            continue
        files = sorted(f for f in os.listdir(d) if f.endswith(".png"))
        if len(files) < 10:
            print("  ⛔ %-8s 本地只有 %d 张（不足 10 张，跳过）" % (loc, len(files)))
            continue

        # ① 已经与本地一致的 → 直接跳过（不浪费配额重传）
        same, detail = already_matching(tok, lid, loc, d, files)
        if same:
            print("  ✅ %-8s 已是本地新图（%d/%d 一致），跳过" % (loc, detail, len(files)))
            progress[loc] = {"uploaded": len(files), "total": len(files),
                             "at": time.strftime("%Y-%m-%d %H:%M:%S"), "skipped": "already_matching"}
            json.dump(progress, open(PROGRESS, "w"), ensure_ascii=False, indent=1)
            continue

        # ② 先删该 locale 的旧 iPhone 图（ASC 是追加语义，不删 = 商店页出现重复轮播）
        # ⚠️⚠️ 删失败**必须中止**（2026-11-16 P0 修正假绿）：
        #   版本已挂进 submission 时 Apple 报 "Can't Delete Screenshot while Ready
        #   For Review" → 旧图删不掉 → 此时继续上传 = 追加同名图 = 商店页重复轮播；
        #   而旧实现把删失败当可忽略 → 整轮报「上传 10/10 ✅」但**一张新图都没传**。
        #   ⇒ 删失败就如实报出来并跳过这个 locale，**绝不能报成功**。
        if not args.keep:
            cur = iphone_shots(tok, lid)
            del_fail = []
            for sid, fname in cur:
                ok, msg = del_shot(tok, sid)
                print("     删 %-28s %s %s" % (fname, "OK" if ok else "FAIL", "" if ok else msg[:90]))
                if not ok:
                    del_fail.append((fname, msg))
            # ⚠️⚠️ 2026-11-16 P0 又一个坑：Apple 的**删除是异步的**。
            #   DELETE 返回 204（成功），但资源还在 set 里没真正移除；
            #   脚本 sleep 2 就开始传 → Apple 报
            #   `screenshots upload: Too many screenshots.: Set: <id>`
            #   （旧 10 张还在 + 传新图 = 超 10 张上限）→ 整批传不上去。
            #   ⇒ 必须**轮询回读**，等 set 里的张数真的降下来再传。
            for _wait in range(30):
                time.sleep(3)
                if len(iphone_shots(tok, lid)) == 0:
                    print("     删已生效（set 清空，用了约 %d 秒）" % ((_wait + 1) * 3))
                    break
            else:
                left = iphone_shots(tok, lid)
                print("     ⚠️ 等了 90 秒 set 里还有 %d 张 → 不上传（会撞上限）" % len(left))
                progress[loc] = {"uploaded": 0, "total": len(files),
                                 "at": time.strftime("%Y-%m-%d %H:%M:%S"),
                                 "error": "delete_not_effective"}
                json.dump(progress, open(PROGRESS, "w"), ensure_ascii=False, indent=1)
                continue

            if del_fail:
                print("  ⛔ %-8s 旧图删除失败 %d 张 → 跳过本 locale（继续传会造成重复轮播）" % (loc, len(del_fail)))
                print("     典型原因：版本已挂在 submission 上 → 需先 `asc review items-remove` 摘下版本条目")
                print("     首例: %s | %s" % (del_fail[0][0], del_fail[0][1][:160]))
                progress[loc] = {"uploaded": 0, "total": len(files),
                                 "at": time.strftime("%Y-%m-%d %H:%M:%S"),
                                 "error": "delete_failed"}
                json.dump(progress, open(PROGRESS, "w"), ensure_ascii=False, indent=1)
                continue

        # ③ 逐张串行传（每张传前记录当前 id 集合 → 传后回读「有没有新增 id」）
        done = 0
        for f in files:
            p = os.path.join(d, f)
            before_ids = {i for i, _ in iphone_shots(tok, lid)}
            ok, state, detail = upload_one(tok, lid, p, f, before_ids)
            done += 1 if ok else 0
            print("     [%2d/%2d] %-28s %s %s" % (done, len(files), f, state,
                                                 "" if ok else detail[:80]))
        progress[loc] = {"uploaded": done, "total": len(files), "at": time.strftime("%Y-%m-%d %H:%M:%S")}
        json.dump(progress, open(PROGRESS, "w"), ensure_ascii=False, indent=1)
        print("  ✅ %-8s 上传 %d/%d" % (loc, done, len(files)))


if __name__ == "__main__":
    main()
