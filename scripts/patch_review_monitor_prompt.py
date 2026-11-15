import io
import json
import os

P = os.path.expanduser("~/.hermes/cron/jobs.json")
OUT = "/tmp/asc_review_monitor_prompt.md"

d = json.load(open(P))
jobs = d if isinstance(d, list) else d.get("jobs", [])
prompt = None
for j in jobs:
    if (j.get("id") or j.get("job_id")) == "ce26352afbfe":
        prompt = j.get("prompt")
        break
if not prompt:
    raise SystemExit("找不到 job ce26352afbfe")

orig = prompt

# ① 监控范围加上时间收纳箱 + 萌宠手册
old_loop = "for id in 6759187331 6820045336 6821559872; do"
new_loop = "for id in 6759187331 6820045336 6821559872 6832234671 6825799483; do"
assert old_loop in prompt, "循环锚点没找到"
prompt = prompt.replace(old_loop, new_loop, 1)

old_map = """**App 对应关系**：
- 6759187331 = 私密记账（1.0.13 于 2026-10-21 提审，等 READY_FOR_SALE；1.0.12 已上架）
- 6820045336 = HabitFlow（1.0）
- 6821559872 = 卡点通勤（1.0）"""
new_map = """**App 对应关系**：
- 6759187331 = 私密记账（1.0.21 已挂 submission，尚未送审，等周五提审窗口）
- 6820045336 = HabitFlow（1.0）
- 6821559872 = 卡点通勤（1.0.5 已上架）
- 6832234671 = 时间收纳箱（1.0，2026-11-15 21:01 已提交审核，等 READY_FOR_SALE）
- 6825799483 = 萌宠手册（1.0.1 已上架）

**2026-11-15 新增监控对象：时间收纳箱 6832234671**
- 1.0 版本、build 12、2026-11-15 21:01 提交（submission 9d751938），releaseType=AFTER_APPROVAL
  （过审自动上架）。等 `appStoreState` 变成 `READY_FOR_SALE` → 报告「时间收纳箱 1.0 已过审上架」。
- **它有 4 个空 submission**（af7f4595 / 217a5188 / 67b53443 / f2f2e4de，items=0、删不掉），
  但**不影响判断** —— 一律以 `appStoreState` 为准（上面那条「reviewState 不可信」的坑同样适用）。
- 变成 `REJECTED` → **必须报告**并附 rejectionReason 全文。
- ⚠️ 「过审」不等于「商店页可访问」：报告已过审后，还必须实测商店页 HTTP 200 才算真上架
  （在审 ≠ 已上架）。命令见 skill `asc-submit-blockers` 的「在审 ≠ 已上架」一节。"""
assert old_map in prompt, "对应关系锚点没找到"
prompt = prompt.replace(old_map, new_map, 1)

assert prompt != orig
io.open(OUT, "w", encoding="utf-8").write(prompt)
print("已生成新 prompt:", OUT, len(prompt), "字")
print("循环已改为:", new_loop)
