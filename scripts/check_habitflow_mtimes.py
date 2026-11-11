import os
import subprocess
import time

C = "/Users/mac/HabitFlow"
files = [
    "ios/HabitFlow/ui/RootView.swift",
    "ios/HabitFlow/ui/SettingsView.swift",
    "ios/HabitFlow/HabitFlowApp.swift",
    "ios/HabitFlowTests/DeploymentTargetGuardTests.swift",
    "ios/HabitFlow/ui/StatsView.swift",
]
now = time.time()
print("现在:", time.strftime("%m-%d %H:%M", time.localtime(now)))
for f in files:
    p = os.path.join(C, f)
    if not os.path.exists(p):
        continue
    st = os.stat(p)
    age = (now - st.st_mtime) / 60.0
    print("  %6.1f 分钟前  %s" % (age, f))
