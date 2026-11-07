#!/usr/bin/env python3
"""把 TimeStash 的 ASC 建 App 记录卡点写进 UNRESOLVED.md 的「未解决」区。"""
import io
import os

PATH = os.path.expanduser('~/.hermes/UNRESOLVED.md')

ENTRY = '''### [上架] TimeStash（时间收纳箱）只差用户在 ASC 网页手动新建 App 记录（2026-11-08 00:5x）

- **现象**：TimeStash 全部技术准备已完成（签名归档通过、50 语言、52/52 测试全绿、10 张 1290×2796 商店截图、商店文案齐备），
  但 App Store Connect 里**还没有 TimeStash 这个 App 记录**，无法上传构建、无法提审。
- **已试过什么**：
  1. 官方 API `POST /v1/apps` → `403 FORBIDDEN_ERROR`（"The resource 'apps' does not allow 'CREATE'"）—— 新建 App 记录**没有公开 API**。
  2. `asc web apps create` → "Session expired"，缓存的网页会话是 2026-10-11 的，已死。
  3. iris 网页 API（`appstoreconnect.apple.com/iris/v1/apps` + web-session.json 的 cookie）→ `401 NOT_AUTHORIZED`。
  4. 开发者门户登录态带不进 ASC：`appstoreconnect.apple.com/apps` 直接跳 `?authResult=FAILED`；
     门户里的 `olympus/v1/session/switchTo/QLJ5YWNC2W` 链接同样弹回登录页。
  5. keychain 里的 `asc:web-session:store` 是同一份 2026-10-11 的旧会话，不是更新的。
- **卡在哪**：刷新 ASC 网页会话**必须**用 Apple ID 密码 + 2FA，只有本人能做。
- **影响**：TimeStash 卡在提审前最后一步，其他都不受影响。
- **需要用户做的**（2 分钟，完整清单在 `/Users/mac/TimeStash/docs/ASC_APP_SETUP.md`）：
  ASC 网页 → 「+」→「新建 App」→ 名称 `时间收纳箱` / 主要语言 简体中文 / 平台 iOS /
  Bundle ID `com.junxf.timestash` / SKU `TIMESTASH01` → 创建 → 说一声「建好了」。
  之后上传构建 / 写 50 语言文案 / 传截图 / 填审核信息 / 提审全部由 agent 完成。

'''

MARKER = '## 未解决\n'

with io.open(PATH, encoding='utf-8') as f:
    s = f.read()

if 'TimeStash（时间收纳箱）只差用户在 ASC 网页手动新建 App 记录' in s:
    print('已存在，跳过')
else:
    assert MARKER in s, '未找到「未解决」区标记'
    s = s.replace(MARKER, MARKER + '\n' + ENTRY, 1)
    with io.open(PATH, 'w', encoding='utf-8') as f:
        f.write(s)
    print('已写入 UNRESOLVED.md')
