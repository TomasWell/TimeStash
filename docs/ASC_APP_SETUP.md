# TimeStash — 在 App Store Connect 里建 App 记录（需要你出手的一步）

日期：2026-11-08
状态：**只差这一步**，其余全部已就绪。

---

## 最省事的做法：跑一条命令

```bash
bash ~/TimeStash/scripts/create_asc_app.sh
```

它会依次做三件事：

1. 提示你输入 **Apple ID 密码 + 两步验证码**（安全交互输入框，密码不落盘、不进命令行历史）；
2. 用你的会话自动建好 App 记录 —— 名称、Bundle ID、SKU、主要语言都已经填好，你不用管；
3. 回读官方 API 确认记录真的建成了。

跑完跟我说一声「建好了」，剩下的全部由我接手。

> 想自己看建了啥，也行：脚本跑完后可以直接看
> https://appstoreconnect.apple.com/apps 里多出来的「时间收纳箱」。

---

## 为什么不写成全自动

新建 App Store Connect 的 App 记录，Apple 的**公开 API 不开放**
（`POST /v1/apps` 返回 `403 FORBIDDEN_ERROR`，明确写着
"The resource 'apps' does not allow 'CREATE'"）。
唯一路径是有一个**活着的 ASC 网页会话**。

2026-11-08 01:1x 把能试的路都试过了：

| 试过的路 | 结果 |
|---|---|
| 官方 API `POST /v1/apps` | ❌ 403，Apple 不开放 |
| `asc web apps create` | ❌ Session expired（本机缓存的会话是 2026-10-11 的） |
| 浏览器里直连 iris API | ❌ 401 NOT_AUTHORIZED |
| 开发者门户 → ASC 会话跳转 | ❌ `authResult=FAILED`（门户会话是活的，但 ASC 侧会话真的死了） |
| Chrome 里存的 ASC cookie | ❌ `myacinfo` 的**值是空的**，提不出可用会话 |
| 通行密钥登录 | ❌ 需要真机确认，无人值守时做不了 |

所以唯一剩下的入口就是**用你的账号重新登一次**。

---

## 如果你想自己在网页上建（也可以，约 2 分钟）

1. 打开 **App Store Connect**（https://appstoreconnect.apple.com/apps）；
2. 点左上角 **「+」** → **「新建 App」**；
3. 四个框**照抄**：

   | 框 | 填什么 |
   |---|---|
   | 名称 | `时间收纳箱` |
   | 主要语言 | 简体中文 |
   | 平台 | iOS |
   | Bundle ID | `com.junxf.timestash` |
   | SKU | `TIMESTASH01` |

   > SKU 必须是 `TIMESTASH01`（全大写、无连字符），我按这个写的构建元数据。

4. 点 **「创建」**，然后跟我说一声「建好了」。

---

## 建好之后我会自动做的事（不用你管）

- 拉新 App ID、创建 1.0 版本记录
- 上传刚打好的 Release 归档（`/tmp/TimeStash.xcarchive`，已验签、已带 App Group 权限、50 语言、图标齐全）
- 写 50 个语言的商店文案（描述、关键词、副标题、隐私政策 URL、支持 URL）
- 上传 10 张商店截图（已抓好，在 `store-assets/screenshots/`）
- 填年龄分级、分类、定价、版权、审核联系方式
- App 隐私问卷（不收集数据）
- 跑 `asc review doctor`，把阻塞项清到 0
- 提审

---

## 当前的准备状态（2026-11-08 01:1x 实测复核）

| 项目 | 状态 |
|---|---|
| Bundle ID | `com.junxf.timestash` ✅ 开发者门户已注册（两个 App ID 都在） |
| Widget Bundle ID | `com.junxf.timestash.widget` ✅ |
| App Group | `group.com.junxf.timestash` ✅ 两个 App ID 都已关联 |
| 描述文件 | v4 ✅ 在本机，entitlement 含 application-groups，有效期到 2027-09-19 |
| 签名归档 | ✅ `/tmp/TimeStash.xcarchive`，1.0(1)，Team QLJ5YWNC2W，已验签 |
| 测试 | ✅ 52/52 全绿（43 单元 + 9 UI），零崩溃 |
| 本地化 | ✅ 50 语言全部进包（100 个 .lproj = 主 App + Widget 各 50），占位符 0 错配 |
| 图标 | ✅ 1024×1024 无 alpha，已进包 |
| 截图 | ✅ 10 张，全部 1290×2796（`store-assets/screenshots/`） |
| 商店文案 | ✅ `docs/store-metadata.md` |
| Git | ✅ `main` + `release/v1.0` 分支（提审与开发已分离） |
