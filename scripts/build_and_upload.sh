#!/bin/bash
# Build a signed archive for TimeStash and upload it to App Store Connect.
#
# build 6 = build 5 + i18n 补键（error_title/error_ok）+ 设置页语言选择器 + 两条守卫
# build 5 = build 4 + App 自己的隐私清单 PrivacyInfo.xcprivacy
#          （build 4 的包里只有 GRDB 库自带的清单，App 自身用 UserDefaults
#            却没声明 —— 属于「App 完整性」，正是上次 2.1 被拒的那一类）
#
# ⚠️ MARKETING_VERSION 必须等于 ASC 的 versionString（这里是 "1.0"）——
#    不一致会被 Apple 拒（私密记账的先例：1.0.16 ↔ build 27）。
# ⚠️ asc builds upload 要的是 .ipa 文件（Payload/ 结构），不是 .app 目录。
set -u
export PATH=$HOME/.blitz/bin:$PATH
export ASC_TIMEOUT=600s
export HTTPS_PROXY=http://127.0.0.1:7890
export HTTP_PROXY=http://127.0.0.1:7890
APP=6820045336
BUNDLE=com.junxf.timestash
TEAM=QLJ5YWNC2W
DD=~/TimeStash/ios/DerivedData
OUT=~/TimeStash/build
IPA="$OUT/TimeStash-1.0.1-build6.ipa"

cd ~/TimeStash/ios || exit 1
mkdir -p "$OUT"

echo "== 0. 确认 build 号 =="
grep -nE 'MARKETING_VERSION|CURRENT_PROJECT_VERSION' project.yml | head -4

echo "== 1. archive =="
xcodebuild archive \
  -project TimeStash.xcodeproj -scheme TimeStash \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath "$OUT/TimeStash.xcarchive" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=$TEAM > /tmp/hf_archive.log 2>&1
RC=$?
echo "  退出码 $RC"
if [ $RC -ne 0 ]; then
  grep -E "error:|Provisioning|Signing" /tmp/hf_archive.log | sed 's|.*/||' | sort -u | head -15
  exit 1
fi

echo "== 2. 校验产物 =="
APP_DIR="$OUT/TimeStash.xcarchive/Products/Applications/TimeStash.app"
if [ ! -d "$APP_DIR" ]; then
  echo "  ❌ 找不到 $APP_DIR"
  find "$OUT/TimeStash.xcarchive/Products" -maxdepth 2 -type d | head -6
  exit 1
fi
echo "  app: $APP_DIR"
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_DIR/Info.plist" | sed 's/^/  bundle: /'
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_DIR/Info.plist" | sed 's/^/  version: /'
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_DIR/Info.plist" | sed 's/^/  build: /'
codesign -dv "$APP_DIR" 2>&1 | grep -E "Authority|TeamIdentifier" | sed 's/^/  /'
echo "  隐私清单: $([ -f "$APP_DIR/PrivacyInfo.xcprivacy" ] && echo '有 ✓' || echo '无 ❌')"
echo "  .lproj 语言数: $(ls -d "$APP_DIR"/*.lproj 2>/dev/null | wc -l | tr -d ' ')"

echo "== 3. 打包 .ipa =="
cd "$OUT" || exit 1
rm -rf Payload "$IPA"
mkdir -p Payload
cp -R "$APP_DIR" Payload/
# ⚠️ zip 的根目录必须包含 Payload/ —— 否则 Apple 报 ITMS-90072
#    "The IPA is invalid. It does not include a Payload directory."
#    （cd Payload && zip ... app）会把内容打成根级 TimeStash.app/，必错。
zip -qry "$IPA" Payload
rm -rf Payload
ls -la "$IPA" | awk '{print "  ipa: " $5 " bytes"}'
echo "  根目录条目: $(unzip -l "$IPA" 2>/dev/null | awk 'NR>3 && NF==4 {print $4}' | head -1)"

echo "== 4. 上传 =="
# ⚠️ --version 必须与 .ipa 内的 CFBundleShortVersionString 一致：
#    ASC 版本槽「1.0」已被 build 2 占用，再传 1.0 会报 90072 版本号冲突；
#    build 3 起 marketing version 是 1.0.1，新 build 必须沿用 1.0.1。
# ⚠️ --build-number 必须是**下一个没被占用的号**（2026-11-07 实测：
#    ASC 上 build 7 已上传（2026-11-06）且挂在 1.0 槽审核中 → 再传 7 会冲突）。
#    build 8 = build 7 + App Shortcuts（长按图标快捷菜单）+ UI 守卫。
asc builds upload --app "$APP" \
  --ipa "$IPA" \
  --version "1.0.1" \
  --build-number "8" 2>&1 | tail -14

echo "== 5. 回读上传状态 =="
asc builds uploads list --app "$APP" 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
for u in d.get('data',[])[:2]:
    a=u.get('attributes',{})
    st=a.get('state',{})
    print('  upload %s %s build=%s state=%s errors=%s' % (
        u.get('id','')[:8], a.get('cfBundleShortVersionString'), a.get('cfBundleVersion'),
        st.get('state'), st.get('errors')))
"
