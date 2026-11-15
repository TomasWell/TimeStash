import io

P = "/Users/mac/.hermes/UNRESOLVED.md"

ANCHOR = "**用户发布后的收尾**：跑 `python3 ~/TimeStash/scripts/submit_timestash.py`"

ADD = (
    "**已装自动收尾（2026-11-15 21:0x）**：cron「时间收纳箱提审看门狗」`b67ebf964660`，\n"
    "每 30 分钟跑 `~/.hermes/scripts/timestash_privacy_watch.py`（monitor 模式）：\n"
    "输出不变（PENDING）就跳过 agent 不烧 LLM；用户一发布隐私问卷，\n"
    "脚本会自动 items-add + submissions-submit → 唤醒 agent 汇报并自删 job。\n"
    "用户**不需要**再专门通知助手。\n\n"
)


def main():
    s = io.open(P, encoding="utf-8").read()
    if "时间收纳箱提审看门狗" in s:
        print("已存在，跳过")
        return
    if ANCHOR not in s:
        print("FAIL: 锚点没找到")
        return
    s = s.replace(ANCHOR, ADD + ANCHOR, 1)
    io.open(P, "w", encoding="utf-8").write(s)
    print("OK: 已写看门狗说明")


if __name__ == "__main__":
    main()
