"""时间收纳箱 1.0 提审脚本（可反复执行）。

两个必须记住的坑（2026-11-15 实测）：

1. **reviewSubmissions 不可删除**：REST DELETE 返回 403。
   `asc review submissions-create` 的并发上限是 **5 个/App**，
   一旦被空壳占满，就再也建不出新的 submission。
   ⇒ 必须**优先复用**已有的空壳（items 为空 + state=READY_FOR_REVIEW）。

2. **空壳不算「已在审」**：它们 state 是 READY_FOR_REVIEW 但 items=0，
   `asc review history` 里不会有它们。判断是否在审要看 version 的状态。

唯一真阻塞：**App 隐私问卷未发布**（必须在 ASC 网页点「发布」），
报错形如：
    Associated errors for /v1/appDataUsages/:
      - You must have published answers to your app's data usages.
注意：`asc review doctor` 和 `asc validate` 都只会给 info，
**只有 items-add 才暴露** —— doctor 的 0 blocking 是假象。
"""
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


def sh(args, timeout=220):
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


def main():
    subs = api(SUBS_URL).get("data", [])
    print("现有 submission:", len(subs))

    # 1) 先找可复用的空壳
    reusable = []
    for it in subs:
        sid = it["id"]
        state = (it.get("attributes") or {}).get("state")
        items = api("https://api.appstoreconnect.apple.com/v1/reviewSubmissions/%s/items" % sid).get("data", [])
        if items:
            print("  %s 已有 items=%d（跳过）" % (sid[:8], len(items)))
            continue
        if state in ("READY_FOR_REVIEW", "PREPARE_FOR_SUBMISSION"):
            reusable.append(sid)
            print("  %s 空壳 state=%s → 可复用" % (sid[:8], state))

    candidates = list(reusable)
    if not candidates:
        out, err, rc = sh(["asc", "review", "submissions-create", "--app", APP,
                            "--platform", "IOS", "--output", "json"])
        if rc != 0:
            print("建 submission 失败:", (err or out)[:600])
            return 3
        try:
            candidates.append(json.loads(out)["data"]["id"])
        except Exception:
            print("建 submission 返回不可解析:", out[:300])
            return 3

    # 2) 逐个试 items-add
    target = None
    last_err = ""
    for sid in candidates:
        out, err, rc = sh(["asc", "review", "items-add", "--submission", sid,
                            "--item-type", "appStoreVersions", "--item-id", VID,
                            "--output", "json"])
        if rc == 0 and not err.strip():
            print("  ✅ 挂到 %s" % sid[:8])
            target = sid
            break
        last_err = err or out
        print("  ❌ %s -> %s" % (sid[:8], last_err.split("\n")[0][:120]))

    if not target:
        print()
        print("全部失败，完整错误：")
        print(last_err[:900])
        if "published answers to your app's data usages" in last_err:
            print()
            print("👉 结论：App 隐私问卷尚未发布。")
            print("   用户操作：https://appstoreconnect.apple.com/apps/%s/appPrivacy" % APP)
            print("   选「此 App 不收集数据」→ 底部点「发布 / Publish」")
        return 2

    # 3) 提交
    out, err, rc = sh(["asc", "review", "submissions-submit", "--id", target,
                       "--confirm", "--output", "json"])
    if rc != 0:
        print("提交失败:", (err or out)[:600])
        return 3
    try:
        print("  提交:", json.loads(out)["data"]["attributes"])
    except Exception:
        print("  提交:", out[:400])

    final = api("https://api.appstoreconnect.apple.com/v1/reviewSubmissions/" + target)
    print("  回读:", json.dumps(final.get("data", {}).get("attributes", {}), ensure_ascii=False))
    v = api("https://api.appstoreconnect.apple.com/v1/appStoreVersions/" + VID)
    a = v.get("data", {}).get("attributes", {})
    print("  版本 appStoreState:", a.get("appStoreState"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
