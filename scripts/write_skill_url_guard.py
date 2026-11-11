#!/usr/bin/env python3
"""把「跨 App 扫 URL 强制解包」和「守卫测试自匹配」两条写进 colorfuledger skill。"""
import io

P = "/Users/mac/.hermes/skills/colorfuledger/SKILL.md"

ANCHOR = "### ⛔⭐⭐⭐ 怎么把 iOS 16 模拟器弄上本机（2026-11-11 全程实测，踩完了）"

ADDITION = """### ⛔⭐⭐⭐ `URL(string:)!` 守卫测试会**把自己扫进去**（2026-11-11 实测）

守卫测试的断言消息里写着字面量：

```swift
XCTAssertTrue(offenders.isEmpty,
    "源码里不许再出现 `URL(string: ...)!` 强制解包（iOS 16 会崩）：\\n" + ...)
```

这行**自己**被 `URL\\s*\\(\\s*string:[^)]*\\)\\s*!` 匹配上 → 每次跑都误报
「源码里有强制解包」，而产品代码里其实一处都没有。

**修法（守卫要守的是产品代码，测试代码不会让用户崩溃）**：
```swift
if p.contains("/Tests/") || p.contains("/UITests/") || p.hasSuffix("Tests.swift") { continue }
```
⚠️ 守卫正在铺到全部 App，**这个坑会跟着复制过去** —— 铺的时候必须带上这条排除。

### ⛔⭐⭐⭐ 跨 App 主动扫，不要等守卫测试一个个报（2026-11-11 实测结果）

扫描脚本：`~/TimeStash/scripts/scan_all_apps_url_force_unwrap.py`
（排除 Tests/UITests 目录，按 `URL(string: ...)!` 和「本地化文案拼进 URL(string:)」两条规则）

**2026-11-11 实测结果**：
| App | minOS | 强解包 | 结论 |
|---|---|---|---|
| 私密记账 | 15.0 | 3（**全在 Widget**） | 主 App 已修；Widget 3 处是 `freeledger://record`（**纯 ASCII，iOS 16 不会崩**），待 1.0.21 顺手改掉 |
| 时间收纳箱 | 16.0 | **0** | ✅ |
| HabitFlow | 16.0 | **0** | ✅ |
| 卡点通勤 | 15.0 | **0** | ✅ |
| DailyMe | 15.0 | **0** | ✅ |
| 萌宠手册 | 15.0 | **0** | ✅ |

⇒ **只有私密记账踩了这个雷**，其它 5 个 App 的 iOS 16 用户是安全的。

**判定「会不会崩」的标准**：
- URL 字符串里**含非 ASCII**（本地化文案、用户输入）→ iOS 16 上 `URL(string:)` 返回 nil → **会崩**
- URL 字符串**纯 ASCII**（如 `freeledger://record`）→ 旧解析也能过 → **不会崩**（但风格上仍该去掉 `!`）

""" + ANCHOR


def main():
    with io.open(P, encoding="utf-8") as f:
        s = f.read()
    if "跨 App 主动扫，不要等守卫测试一个个报" in s:
        print("已存在，跳过")
        return
    if ANCHOR not in s:
        print("FAIL: 锚点没找到")
        return
    s = s.replace(ANCHOR, ADDITION, 1)
    with io.open(P, "w", encoding="utf-8") as f:
        f.write(s)
    print("OK: 已写入守卫自匹配坑 + 跨 App 扫描结论")


if __name__ == "__main__":
    main()
