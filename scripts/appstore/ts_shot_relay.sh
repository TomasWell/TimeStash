#!/bin/bash
# TimeStash 商店页截图「接力」任务
# 作用：等 make_store_screenshots.sh --all 跑完（48 locale 全拍完）后，
#       再跑一轮上传（补传剩余 locale），最后跑 --verify 独立回读，
#       并把结果写成 JSON 供下一轮 P0 档读取。
#
# ⚠️ 之所以要接力：upload_ts_shots.py --all 只处理「本地已拍完（10 张）」的 locale。
#    第一轮上传跑的时候拍摄才到 26/48 → 跑完就退出，剩下 22 个没人传。
#    → 必须等拍摄全部结束后再跑第二轮。

set -u
cd /Users/mac/TimeStash || exit 1
SC=/Users/mac/hermes-workspace/appstore/scripts
OUT="$SC/ts_shot_relay.json"

log() { echo "[relay $(date '+%H:%M:%S')] $*"; }

log "等待拍摄任务结束…"
while ps -p 40144 >/dev/null 2>&1; do
  n=$(ls -d /Users/mac/TimeStash/store-assets/screenshots/*/ 2>/dev/null | while read -r d; do
        ls "$d"/*.png 2>/dev/null | wc -l | tr -d ' '
      done | awk '$1>=10{c++} END{print c+0}')
  log "已拍完 $n/48"
  sleep 120
done

log "拍摄结束，开始补传剩余 locale"
cd "$SC" || exit 1
python3.11 upload_ts_shots.py --all > "$SC/relay_upload.log" 2>&1
log "上传结束（exit=$?），开始独立回读 --verify"
python3.11 upload_ts_shots.py --verify > "$SC/relay_verify.log" 2>&1
rc=$?

n=$(ls -d /Users/mac/TimeStash/store-assets/screenshots/*/ 2>/dev/null | while read -r d; do
      ls "$d"/*.png 2>/dev/null | wc -l | tr -d ' '
    done | awk '$1>=10{c++} END{print c+0}')

cat > "$OUT" <<JSON
{
  "finished_at": "$(date '+%Y-%m-%d %H:%M:%S')",
  "shot_locales_10plus": $n,
  "upload_exit": $rc,
  "verify_log": "$SC/relay_verify.log",
  "upload_log": "$SC/relay_upload.log"
}
JSON
log "接力完成：拍完 $n/48，verify 退出码 $rc"
