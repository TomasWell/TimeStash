#!/usr/bin/env python3
"""记录：时间收纳箱 1.0 提审只差「App 隐私问卷发布」这一项（需用户网页操作）。"""
import io

P = "/Users/mac/.hermes/UNRESOLVED.md"
MARKER = "\n## 已解决\n"

ADD = """
### [上架] 时间收纳箱 1.0 提审只差「App 隐私问卷发布」—— 需用户在 ASC 网页点一下（2026-11-15）

**已完成（全部就绪，等这一项）**：
- ✅ build 12 已上传并 VALID（`0fc09abd-f053-4f3f-8154-1b8095d0c89c`），
  **含 11-14 的 i18n 修复**（build 11 上传于 11-11 15:07，不含 8ee8a02 的 33 处修复，
  界面上会直接显示本地化 key 名 → 必须用 build 12）
- ✅ build 12 已挂到 1.0（version id `46a2877b-8ab7-4884-8b21-cfc4583ad3a9`）
- ✅ 出口合规已声明（`usesNonExemptEncryption: false`）—— 换 build 要重新设一次
- ✅ `asc review doctor` → **errors 0 / warnings 0 / blocking 0**
- ✅ `asc validate` → 只剩 1 个 info（见下）
- ✅ 商店页 48 locale：name / subtitle / privacyPolicyUrl 全齐、每个 locale 10 张截图
- ✅ 测试 55 个用例通过（xcresult 权威口径 `passedTests=55`）

**唯一阻塞**（`asc validate` 的 info + `items-add` 的真实报错）：
```
privacy.publish_state.unverified — App Privacy publish state is not verifiable via the public API
                                   and may still block submission
Associated errors for /v1/appDataUsages/: You must have published answers to your app's data usages.
```
⚠️ **doctor 报 0 blocking 是假象** —— App 隐私问卷不在公开 API 里，
doctor 和 validate 都只能给 info，**只有 items-add 才会暴露**。

**为什么必须用户操作**：发布隐私问卷要走 ASC 网页登录（Apple ID 密码 + 2FA）。
`asc web privacy pull/apply/publish` 报「Session expired / password is required」，
浏览器里的 ASC 会话也已过期。助手不代持凭据。

**用户操作（一次性，3 步）**：
1. 打开 **https://appstoreconnect.apple.com/apps/6832234671/appPrivacy**
2. 隐私问卷选 **「此 App 不收集数据」（Data Not Collected）**，
   如果已经是这个答案就**不用改**，直接下一步
3. 页面底部点 **「发布」/ Publish**

**填「不收集数据」的依据（2026-11-15 代码扫描，脚本
`~/TimeStash/scripts/audit_timestash_privacy.py`）**：
- 网络请求（URLSession / http(s) / CFNetwork）：**0 处**
- 第三方 SDK / 追踪（Firebase / Sentry / Amplitude / 广告 SDK…）：**0 处**
- 账号 / 登录（Sign in with Apple / 认证）：**0 处**
- iCloud / CloudKit：**0 处**
- App Group：**2 处**（`AppDatabase.swift:41-42`）—— 只是 **App 与 Widget 共享同一份本地数据库**，
  数据不出设备，不属于「收集数据」

**用户发布后的收尾**：跑 `python3 ~/TimeStash/scripts/submit_timestash_1_0.py`
（脚本会自动建新 submission → 挂版本 → 提交 → 回读验证）。
⚠️ 提审时会新建 submission；**`asc review submissions-delete` 不存在**，
本轮已经产生 5 个空壳（items-add 失败时每次换一个），
它们不影响下次提审，但别把空壳当「已在审」。

"""


def main():
    s = io.open(P, encoding="utf-8").read()
    if "时间收纳箱 1.0 提审只差" in s:
        print("已存在，跳过")
        return
    if MARKER not in s:
        print("FAIL: 没找到锚点")
        return
    s = s.replace(MARKER, ADD + MARKER, 1)
    io.open(P, "w", encoding="utf-8").write(s)
    print("OK: 已写入隐私问卷待办条目")


if __name__ == "__main__":
    main()
