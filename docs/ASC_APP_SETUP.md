# TimeStash — ASC 建 App 记录（需你点的一步）

日期：2026-11-08
状态：**只差这一步**，其余全部已就绪。

---

## 为什么必须你来做

新建 App Store Connect 的 App 记录，Apple 的公开 API 不开放
（`POST /v1/apps` 返回 `403 FORBIDDEN_ERROR`，明确写着 "The resource 'apps'
does not allow 'CREATE'"）。唯一路径是登录 ASC 网页手动创建。

我这边 `asc web apps create` 需要一个还活着的 Apple ID 网页会话，
本机缓存的会话是 2026-10-11 的，已经过期了。

## 你要做的（约 2 分钟）

1. 打开 **App Store Connect**（https://appstoreconnect.apple.com/apps）
   —— 浏览器已登录的话直接进；没登录就用你的 Apple ID 登一下。

2. 点左上角 **「+」** → **「新建 App」**。

3. 四个框**照抄**：

   | 框 | 填什么 |
   |---|---|
   | 名称 | `时间收纳箱` |
   | 主要语言 | 简体中文 |
   | 平台 | iOS |
   | Bundle ID | `com.junxf.timestash` |
   | SKU | `TIMESTASH01` |

   > SKU 必须是 `TIMESTASH01`（全大写、无连字符），我按这个写的构建元数据。

4. 点 **「创建」**。

5. 回来跟我说一句「建好了」，我就接着跑剩下的全部流程。

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

## 当前的准备状态（已验证）

| 项目 | 状态 |
|---|---|
| Bundle ID | `com.junxf.timestash` ✅ 已在开发者门户注册 |
| Widget Bundle ID | `com.junxf.timestash.widget` ✅ |
| App Group | `group.com.junxf.timestash` ✅ 两个 App ID 都已关联 |
| 描述文件 | v4 ✅ 已装到本机，entitlement 含 application-groups |
| 签名归档 | ✅ Release 归档通过，Apple Distribution 签发 |
| 测试 | ✅ 52/52 全绿（43 单元 + 9 UI） |
| 本地化 | ✅ 50 语言全部进包，占位符 0 错配 |
| 图标 | ✅ 1024×1024 无 alpha，已进包 |
| 截图 | ✅ 10 张（`store-assets/screenshots/`） |
| 商店文案 | ✅ `docs/store-metadata.md` |
| Git | ✅ `main` + `release/v1.0` 分支（提审与开发已分离） |
