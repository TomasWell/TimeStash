#!/bin/bash
# TimeStash：在 App Store Connect 里新建 App 记录（一步到位）。
#
# 用法：bash ~/TimeStash/scripts/create_asc_app.sh
#
# 做了什么：
#   1. 先用 asc web auth login 刷新网页会话（需要你的 Apple ID 密码 + 2FA，
#      密码不落盘、不进命令行历史 —— asc 会用安全交互提示框收）。
#   2. 会话有了之后，调 asc web apps create 建 App 记录（全部参数已填好）。
#   3. 回读官方 API 确认记录真的建出来了。
#
# 为什么必须你来做这一步：Apple 的公开 API 不允许新建 App 记录
# （POST /v1/apps 明确返回 403 "The resource 'apps' does not allow 'CREATE'"），
# 唯一的路径就是登录 ASC 的网页会话。

set -uo pipefail
export PATH="$HOME/.blitz/bin:$PATH"

APP_NAME="时间收纳箱"
BUNDLE_ID="com.junxf.timestash"
SKU="TIMESTASH01"
PRIMARY_LOCALE="zh-Hans"
APPLE_ID="${ASC_APPLE_ID:-tomaswell163@gmail.com}"

echo "=== 1/3 刷新 App Store Connect 网页会话 ==="
echo "（接下来会提示你输入 Apple ID 密码和两步验证码；密码不会保存到任何文件）"
echo
asc web auth login --apple-id "$APPLE_ID" || {
  echo "❌ 网页会话没登录成功，先不往下走。"; exit 1;
}

echo
echo "=== 2/3 新建 App 记录 ==="
asc web apps create \
  --name "$APP_NAME" \
  --bundle-id "$BUNDLE_ID" \
  --sku "$SKU" \
  --primary-locale "$PRIMARY_LOCALE" \
  --platform IOS \
  --version 1.0 \
  --output json
rc=$?

echo
echo "=== 3/3 回读官方 API 确认 ==="
python3 - <<'PY'
import json, os, subprocess
env = dict(os.environ, PATH=os.path.expanduser("~/.blitz/bin") + ":" + os.environ.get("PATH", ""))
p = subprocess.run(["asc", "apps", "list", "--output", "json"],
                   capture_output=True, text=True, timeout=300, env=env)
try:
    d = json.loads(p.stdout)
except Exception:
    print("❌ 读 App 列表失败:", (p.stderr or p.stdout)[:300]); raise SystemExit(1)
hit = [a for a in d.get("data", [])
       if (a.get("attributes") or {}).get("bundleId") == "com.junxf.timestash"]
if hit:
    a = hit[0]["attributes"]
    print("✅ 建好了：%s | bundleId=%s | sku=%s | id=%s"
          % (a.get("name"), a.get("bundleId"), a.get("sku"), hit[0]["id"]))
else:
    print("❌ 没查到 com.junxf.timestash —— 建记录没成功")
    for a in d.get("data", []):
        at = a.get("attributes") or {}
        print("   现有：", at.get("name"), "|", at.get("bundleId"))
    raise SystemExit(1)
PY
