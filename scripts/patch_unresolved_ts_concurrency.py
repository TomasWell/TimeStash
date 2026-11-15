import io

P = "/Users/mac/.hermes/UNRESOLVED.md"

OLD = (
    "**用户发布后的收尾**：跑 `python3 ~/TimeStash/scripts/submit_timestash_1_0.py`\n"
    "（脚本会自动建新 submission → 挂版本 → 提交 → 回读验证）。\n"
    "⚠️ 提审时会新建 submission；**`asc review submissions-delete` 不存在**，\n"
    "本轮已经产生 5 个空壳（items-add 失败时每次换一个），\n"
    "它们不影响下次提审，但别把空壳当「已在审」。"
)

NEW = (
    "**用户发布后的收尾**：跑 `python3 ~/TimeStash/scripts/submit_timestash.py`\n"
    "（脚本会**优先复用**已有空壳 → 挂版本 → 提交 → 回读验证）。\n"
    "\n"
    "⚠️⚠️ **reviewSubmissions 的三个坑（2026-11-15 踩到）**：\n"
    "1. **不可删除**：REST `DELETE /v1/reviewSubmissions/{id}` 返回 **403**。\n"
    "2. **并发上限 5 个/App**：`asc review submissions-create` 报\n"
    "   `maximum limit=5 of concurrency has reached` —— 空壳占满后就建不出新的了。\n"
    "   ⇒ **提审脚本必须优先复用空壳**（items=0 且 state=READY_FOR_REVIEW），\n"
    "   绝不能「失败就换一个新建的」。\n"
    "3. **空壳不是「已在审」**：state=READY_FOR_REVIEW 但 items=0，\n"
    "   `asc review history` 里查不到它们。判断是否真在审要看 **version 的状态**。\n"
    "\n"
    "本轮已产生 5 个空壳（`9d751938` / `af7f4595` / `217a5188` / `67b53443` / `f2f2e4de`），\n"
    "删不掉，但**可复用**（脚本已改成复用）。"
)


def main():
    s = io.open(P, encoding="utf-8").read()
    if "并发上限 5 个/App" in s:
        print("已存在，跳过")
        return
    if OLD not in s:
        print("FAIL: 锚点没找到")
        return
    s = s.replace(OLD, NEW, 1)
    io.open(P, "w", encoding="utf-8").write(s)
    print("OK: 已补并发上限坑")


if __name__ == "__main__":
    main()
