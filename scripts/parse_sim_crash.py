import json
import os
import subprocess
import sys

REPORT = os.path.expanduser("~/Library/Logs/DiagnosticReports/ColorFuLedger-2026-11-11-200523.ips")
raw = open(REPORT, encoding="utf-8").read()
head, _, body = raw.partition("\n")
meta = json.loads(head)
d = json.loads(body)

print("=== 崩溃基本信息 ===")
print("  app:", meta.get("app_name"), meta.get("app_version"), "build", meta.get("build_version"))
print("  os:", meta.get("os_version"), "| 机型:", meta.get("modelCode") or d.get("modelCode"))
print("  时间:", meta.get("timestamp"))
print("  exception:", json.dumps(d.get("exception"), ensure_ascii=False))
print("  termination:", json.dumps(d.get("termination"), ensure_ascii=False))
print("  bug_type:", meta.get("bug_type"))

print("\n=== 崩溃线程栈（前 12 帧）===")
for t in d.get("threads", []):
    if not t.get("triggered"):
        continue
    for i, f in enumerate(t.get("frames", [])[:12]):
        sym = f.get("symbol", "")
        img = f.get("imageIndex")
        name = f.get("imageOffset")
        print("  %2d  %-16s %-12s %s" % (i, "image %s" % img, name, sym[:90]))
    break

# 符号化：用 build 28 模拟器产物的 dSYM
dsym = "/tmp/fl-dd28rel/Build/Products/Debug-iphonesimulator/ColorFuLedger.app.dSYM"
if not os.path.exists(dsym):
    dsym = "/tmp/fl-dd28rel/Build/Products/Release-iphonesimulator/ColorFuLedger.app.dSYM"
print("\n=== 符号化（dSYM: %s, 存在=%s）===" % (dsym, os.path.exists(dsym)))

if os.path.exists(dsym):
    # 找 load address
    base = None
    for img in d.get("usedImages", []):
        if img.get("name") == "ColorFuLedger":
            base = img.get("base")
            break
    print("  binary base:", hex(base) if base else "?")
    frames = []
    for t in d.get("threads", []):
        if t.get("triggered"):
            for f in t.get("frames", [])[:12]:
                frames.append((f.get("imageIndex"), f.get("imageOffset")))
            break
    used = d.get("usedImages", [])
    addrs = []
    for imgIdx, off in frames:
        img = used[imgIdx] if imgIdx < len(used) else None
        if img and img.get("name") == "ColorFuLedger":
            addrs.append(hex(base + off))
        else:
            addrs.append(None)
    valid = [a for a in addrs if a]
    if valid:
        cmd = ["atos", "-arch", "arm64", "-o", os.path.join(dsym, "Contents/Resources/DWARF/ColorFuLedger"),
               "-l", hex(base)] + valid
        out = subprocess.run(cmd, capture_output=True, text=True).stdout.strip().split("\n")
        idx = 0
        print()
        for i, (imgIdx, off) in enumerate(frames):
            img = used[imgIdx] if imgIdx < len(used) else {}
            if img.get("name") == "ColorFuLedger" and idx < len(out):
                print("  %2d  %-28s %s" % (i, hex(base + off), out[idx]))
                idx += 1
            else:
                print("  %2d  [%s]" % (i, img.get("name", "?")))
