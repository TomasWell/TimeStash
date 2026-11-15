import io
import re

P = "/Users/mac/.hermes/UNRESOLVED.md"

START = "### [上架] 时间收纳箱 1.0 提审只差「App 隐私问卷发布」—— 需用户在 ASC 网页点一下（2026-11-15）"
RESOLVED_MARK = "## 已解决\n"

ENTRY = """
### [上架] ✅ 时间收纳箱 1.0 已提交审核（2026-11-15 21:01）

- **提交时间**：2026-11-15T13:01:33Z（北京时间 21:01）
- **submission**：`9d751938-c17e-4dce-8efb-f1386859c0b6`（复用了一个空壳，没新建）
- **版本状态**：`WAITING_FOR_REVIEW`；`blockers = None`；
  `nextAction = "Wait for App Store review outcome."`
- **releaseType**：`AFTER_APPROVAL`（过审自动上架，不用手动发）
- **用的 build**：`0fc09abd-f053-4f3f-8154-1b8095d0c89c`（build 12，VALID），
  含 11-14 的 i18n 修复（33 处界面直接显示本地化 key 的问题）
- **卡点如何解除**：用户 2026-11-15 在 ASC 网页发布了 App 隐私问卷（选「此 App 不收集数据」）。
  证据：发布前 `items-add` 报 `You must have published answers to your app's data usages`，
  发布后同一条命令直接成功。
- **看门狗 cron 已删除**（`b67ebf964660`，任务完成）。
  脚本保留在 `~/.hermes/scripts/timestash_privacy_watch.py`，
  完成标记在 `~/.hermes/cache/scratch/timestash_submitted.marker`。
- **遗留**：Apple 侧结果未知，需轮询；过审后上架仍要实测商店页 HTTP 200
  （在审 ≠ 已上架，见 skill `asc-submit-blockers`）。
- **注意**：还有 4 个空壳 submission（`af7f4595` / `217a5188` / `67b53443` / `f2f2e4de`）
  删不掉（403），但**可复用**，别当「已在审」。

"""


def main():
    s = io.open(P, encoding="utf-8").read()
    if "时间收纳箱 1.0 已提交审核" in s:
        print("已存在，跳过")
        return

    # 把「未解决」区的那一条整段挪到「已解决」区
    i = s.find(START)
    if i < 0:
        print("FAIL: 找不到待办条目")
        return
    # 找到该条目到下一个 "### " 或 "## " 为止
    j = s.find("\n### ", i + 10)
    if j < 0:
        j = s.find("\n## ", i + 10)
    if j < 0:
        j = len(s)
    block = s[i:j].strip()
    s = s[:i] + s[j:]

    if RESOLVED_MARK not in s:
        print("FAIL: 找不到「已解决」锚点")
        return
    s = s.replace(RESOLVED_MARK, RESOLVED_MARK + ENTRY, 1)
    io.open(P, "w", encoding="utf-8").write(s)
    print("OK: 已从「未解决」移到「已解决」（原段落 %d 字）" % len(block))


if __name__ == "__main__":
    main()
