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
APP="${APP:-6832234671}"
BUNDLE=com.junxf.timestash
TEAM=QLJ5YWNC2W
DD=~/TimeStash/ios/DerivedData
OUT=~/TimeStash/build
# ⚠️ build 号**不能写死**（2026-11-16 P0 实测修）：原来这里写死 "11"，
# 而 project.yml 已经升到 13 → 上传时声明的号与包里的号不一致 → Apple 报
# 90345 Metadata/Info.plist Mismatch，反复重传都一样。
# 现在从 project.yml 动态读，两处版本号永远一致。
read -r MV CV < <(python3.11 - <<'PY'
import re
s = open('/Users/mac/TimeStash/ios/project.yml', encoding='utf-8').read()
mv = re.search(r'MARKETING_VERSION:\s*"([^"]+)"', s)
cv = re.search(r'CURRENT_PROJECT_VERSION:\s*"(\d+)"', s)
print(mv.group(1) if mv else "1.0", cv.group(1) if cv else "1")
PY
)
IPA="$OUT/TimeStash-${MV}-build${CV}.ipa"
echo "== 版本号（从 project.yml 读）== marketing=$MV build=$CV ipa=$IPA"

cd ~/TimeStash/ios || exit 1
mkdir -p "$OUT"

echo "== 0. 确认 build 号 =="
grep -nE 'MARKETING_VERSION|CURRENT_PROJECT_VERSION' project.yml | head -4

echo "== 1. archive =="
xcodegen generate >/dev/null && xcodebuild archive \
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
# ⚠️ --version 必须与 .ipa 内的 CFBundleShortVersionString 一致（现为 1.0，project.yml 的 MARKETING_VERSION）——
#    不一致会被 Apple 拒（ITMS-90345 Metadata/Info.plist Mismatch ✅）。
asc builds upload --app "$APP" \
  --ipa "$IPA" \
  --version "$MV" \
  --build-number "$CV" 2>&1 | tail -14

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

echo "== 6. 加密豁免（必做 + 必须回读，否则 doctor 报 blocking）=="
# ⚠️ 只设标志不够：build 7 上传后这个键整个不存在 → doctor 报 build.encryption.missing
#    → 提不了审。所以设完必须**回读确认**，不能只看命令返回。
# 纯本地 App + Apple 标准框架 → 豁免，无需 PDF 声明。
# ⚠️⚠️ `asc builds list` 的 attributes.version 字段是 **build 号**（13），
#    **不是** marketing version（1.0）！原来按 version=="$MV" 过滤 → 永远找不到
#    → 脚本每次都报「还没找到 VALID 的 build」，豁免步骤被静默跳过。
#    这里按 **build 号**（$CV）过滤。
sleep 20
BID=$(asc builds list --app "$APP" --output json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
items=d if isinstance(d,list) else d.get('data',[])
for b in items:
    a=b.get('attributes',{})
    if a.get('version')=='$CV' and a.get('processingState')=='VALID':
        print(b['id']); break
")
if [ -n "$BID" ]; then
  asc builds update --build-id "$BID" --uses-non-exempt-encryption=false 2>&1 | tail -2
  echo "  回读 usesNonExemptEncryption:"
  asc builds list --app "$APP" --output json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
items=d if isinstance(d,list) else d.get('data',[])
for b in items:
    a=b.get('attributes',{})
    if a.get('version')=='$CV':
        print('    build', a.get('version'), 'processingState=', a.get('processingState'),
              'usesNonExemptEncryption=', a.get('usesNonExemptEncryption'), 'id=', b.get('id'))
"
else
  echo "  ⚠️ 还没找到 VALID 的 build $CV，稍后重跑这一步"
fi
