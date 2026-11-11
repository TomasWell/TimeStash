import os
import re

FILES = [
    ("HabitFlow", "/Users/mac/HabitFlow/ios/HabitFlowTests/URLConstructionGuardTests.swift"),
    ("卡点通勤", "/Users/mac/CommutePilot/ios/CommutePilotTests/URLConstructionGuardTests.swift"),
    ("DailyMe", "/Users/mac/DataMe/ios/DataMeTests/URLConstructionGuardTests.swift"),
    ("萌宠手册", "/Users/mac/PawRecord/ios/PawRecordTests/URLConstructionGuardTests.swift"),
    ("时间收纳箱", "/Users/mac/TimeStash/ios/TimeStashTests/URLConstructionGuardTests.swift"),
]

PAT = re.compile(r"Tests/|UITests|sourceRoot|enumerator|excluded|skip|strippingComments", re.I)

for name, p in FILES:
    print("=== %s ===" % name)
    if not os.path.exists(p):
        print("   文件不存在:", p)
        print()
        continue
    lines = open(p, encoding="utf-8").read().split("\n")
    print("   总行数:", len(lines))
    hits = [(i + 1, l.strip()[:120]) for i, l in enumerate(lines) if PAT.search(l)]
    for n, l in hits[:12]:
        print("   %4d  %s" % (n, l))
    if len(hits) > 12:
        print("   ... 共 %d 行命中" % len(hits))
    print()
