import os
import re
import subprocess

ROOT = "/Users/mac/TimeStash/ios"
TESTS = os.path.join(ROOT, "TimeStashTests")
PBX = os.path.join(ROOT, "TimeStash.xcodeproj/project.pbxproj")

files = sorted(f for f in os.listdir(TESTS) if f.endswith(".swift"))
print("TimeStashTests 目录里 %d 个 .swift 文件：" % len(files))
for f in files:
    print("   ", f)

text = open(PBX, encoding="utf-8").read()
print()
print("=== 是否在 pbxproj 里 ===")
missing = []
for f in files:
    base = f[:-6]
    if base not in text:
        missing.append(f)
print("  不在 pbxproj 的:", missing if missing else "无（全部在）")

print()
print("=== 最近提交是否新增了测试文件 ===")
out = subprocess.run(["git", "-C", "/Users/mac/TimeStash", "log", "--diff-filter=A",
                      "--name-only", "--format=%h %ad %s", "--date=short",
                      "--", "ios/TimeStashTests/"],
                     capture_output=True, text=True).stdout
print(out[:1500])
