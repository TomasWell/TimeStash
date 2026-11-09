#!/usr/bin/env python3
"""统计某个 App 某个版本下，每个 locale 的商店截图数量。

⚠️ 2026-11-09 实测踩坑：`asc screenshots list --output json` 的结构**不是**
标准 REST 的 `{"data": [...]}`，而是：

    {"versionLocalizationId": "...",
     "sets": [{"set": {...}, "screenshots": [{...}, ...]}, ...]}

按 `d.get("data", [])` 取会**全部取空 → 误报「48 个 locale 零截图」**，
而实际上截图都在（1.0.17/1.0.18 每个 locale 5 张 APP_IPHONE_67）。

同样的坑还有（memory #254）：Apple 接口**查询失败**与**没有**必须区分开。
"""
import json
import os
import subprocess
import sys
import collections


def main():
    env = dict(os.environ)
    env["PATH"] = "/Users/mac/.blitz/bin:" + env.get("PATH", "")

    vlocs_path = sys.argv[1] if len(sys.argv) > 1 else "/tmp/vlocs.json"
    with open(vlocs_path, encoding="utf-8") as f:
        d = json.load(f)

    counts = {}
    zero = []
    for it in d.get("data", []):
        loc = it["attributes"].get("locale")
        lid = it["id"]
        out = subprocess.run(
            ["asc", "screenshots", "list", "--version-localization", lid, "--output", "json"],
            capture_output=True, text=True, env=env).stdout
        try:
            j = json.loads(out)
        except Exception:
            zero.append((loc, "PARSE_FAIL"))
            continue
        if "error" in j or "_error" in j:
            zero.append((loc, "QUERY_FAILED"))
            continue
        n = 0
        for s in j.get("sets", []):
            n += len(s.get("screenshots", []) or [])
        counts[loc] = n
        if n == 0:
            zero.append((loc, 0))

    with_img = sum(1 for v in counts.values() if v > 0)
    print("有图 locale: %d / %d" % (with_img, len(counts)))
    print("图数分布:", dict(collections.Counter(counts.values())))
    print("零图/查询失败:", zero[:12])
    for k in ("zh-Hans", "en-US", "zh-Hant"):
        print("  %-8s -> %s 张" % (k, counts.get(k)))
    return 0 if not zero else 1


if __name__ == "__main__":
    sys.exit(main())
