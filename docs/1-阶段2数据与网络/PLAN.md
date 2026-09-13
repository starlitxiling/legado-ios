# 阶段 2 计划：数据与网络

> 状态：**已确认**（2026-09-13，人类以 `/goal` 授权：一直做到 iOS 应用可构建；WebDAV 测试账号只读；书源与单元顺序由 Agent 定）。轮次在 `ios` 分支直接进行（等价 `/start --no-worktree`），因为 `ios` 是 orphan 分支，按主分支开 worktree 会切到 Android 代码。

## 1. 结论先行

- 阶段 2 拆成 **6 个单元**，每个单元一次 Codex 调用、一次独立复审、按 Kotlin 返修、提交。顺序由依赖决定：网络层 → 宿主网络方法 → 实体与导入 → WebBook 流程 → GRDB → 备份与 WebDAV。
- **两条设计原则**贯穿全部单元：① 网络与文件系统一律经 protocol 注入，测试用假实现，不发真实请求；② Kotlin 端 `model/webBook/`、`data/entities/`、`help/http/` 是规格，规格文档只补写行为契约，不再逐行翻译成中文规格（阶段 1 证明 Kotlin 直读 + 复审比二手规格可靠）。
- 完成判据与 PROMPT 一致；真机冒烟由人类执行并回报结果。

## 2. 单元划分

| 单元 | 内容 | Kotlin 规格 | 离线验证 |
| --- | --- | --- | --- |
| **U1 网络层** | `HttpClient` protocol + URLSession 实现；把 `UrlOptions` 映射到请求（method、headers、body 编码、charset 解码含 GBK / GB18030、retry、followRedirects、timeout 派生）；响应字符集探测顺序（header → meta → 默认）；Cookie 存储按域名，语义对齐 `CookieStore`；`StrResponse` 模型（url、body、code、headers） | `help/http/HttpHelper.kt`、`help/http/*`、`model/analyzeRule/AnalyzeUrl.kt` 请求段、`help/CookieStore.kt` | 假 `HttpClient` 回放录制的响应；用例覆盖各选项与失败路径 |
| **U2 宿主网络方法** | `JavaHost` 的 `ajax` / `ajaxAll` / `get` / `post` / `head` / `connect` / `getCookie` / `cacheFile` 等一级二级方法；失败返回错误字符串并继续；`cookie` / `cache` 注入对象的真实实现 | `help/JsExtensions.kt`（网络段）、`help/CacheManager.kt` | 假 `HttpClient`；JS 层用例覆盖成功、超时、非 2xx、异常 |
| **U3 实体与导入** | `BookSource`（6 组规则对象）、`ReplaceRule`、`Book`、`BookChapter`、`SearchBook`、`BookGroup`、`Cookie`、`ReadRecord`、`Bookmark` 的 Codable 模型；导入解析：source 数组 / url 数组、规则字段对象或字符串两种写法、`StringJsonDeserializer` / `IntJsonDeserializer` 弱类型容错、非 JSON 文本判为纯 JS 书源（本轮只识别不执行） | `data/entities/*`、`data/entities/rule/*`、`utils/GsonExtensions.kt`、`ui/association/BookSourceImport.kt` | 用阶段 0 语料里脱敏后的 20 条书源 JSON 做导入 round-trip 测试（只用结构，不含站点内容） |
| **U4 WebBook 流程** | `BookList`（搜索 / 发现，含 `checkKeyName`、`ruleSearch.bookList` 为空时的单书处理）、`BookInfo`、`BookChapterList`（`nextTocUrl` 分页、去重、`ruleToc` 各字段）、`BookContent`（`nextContentUrl` 分页、`replaceRegex`、`webJs`、标题 / 正文拼接）；并发与超时策略按 `concurrentRate` | `model/webBook/BookList.kt`、`BookInfo.kt`、`BookChapterList.kt`、`BookContent.kt`、`help/book/ContentProcessor.kt` | 自造 HTML fixture + 假客户端，端到端跑四条流程；期望值按 Kotlin 推导并逐条回源复审 |
| **U5 GRDB** | schema（MVP 表）、迁移基线、Repository（书架增删改查、章节批量写入、搜索缓存、替换规则、阅读进度）；字段以 `data/entities` 为规格，不翻译 Room 迁移 | `data/dao/*`、`data/AppDatabase.kt` 的实体定义 | 内存数据库单测 |
| **U6 备份与 WebDAV** | Legado 备份包解析（`bookSource.json`、`bookshelf.json`、`replaceRule.json`、`readRecord`、`bookmark`）导入落库；WebDAV 客户端（Basic 认证、PROPFIND、GET / PUT）经 `HttpClient` 注入 | `help/storage/Backup.kt`、`Restore.kt`、`lib/webdav/*` | 自造备份包 fixture；WebDAV 用假客户端回放 PROPFIND / GET |

## 3. 关键设计决策

| 决策 | 结论 | 理由 |
| --- | --- | --- |
| 网络抽象 | `HttpClient` protocol，`URLSessionHttpClient` 为生产实现，`ReplayHttpClient` 为测试实现 | 宪法要求测试不发真实请求；引擎与宿主方法都只依赖 protocol |
| 并发模型 | Swift async/await；`AnalyzeRule` 及各引擎实例**不跨任务共享**，每次请求新建；Cookie / Cache 存储用 actor | 阶段 1 的引擎是可变对象，未设计线程安全；复刻 Kotlin「每次解析新建」的用法最省事 |
| 字符集 | 解码顺序 header charset → HTML meta → `UrlOptions.charset` → UTF-8；GB 系列用 `CFStringConvertEncoding` | 对齐 `EncodingDetect` 的实际行为，具体顺序在 U1 回源核对 |
| 不支持项 | `dnsIp` / `resolveIp`、代理、Cronet 特有选项：解析保留、执行忽略并记日志 | iOS 无原生对应；写进 `docs/spec/network-compat.md` |
| 持久化 | GRDB，表结构对齐实体，不翻译 Room 111 版迁移；首次安装即最新 schema | PLAN §2.3 已定 |
| 纯 JS 书源（`mainJs`） | 本轮只识别并标注不支持 | 语料中占比待 U3 统计后决定是否进阶段 4 |

## 4. 已确认项

1. **WebDAV 冒烟环境**：人类提供坚果云测试账号，凭据在 `.env.local`（gitignored，`.env.example` 给占位）。**只读使用**：测试与冒烟只发 PROPFIND / GET，禁止 PUT / DELETE / MKCOL / MOVE；WebDAV 客户端的写方法在本轮不对真实服务器调用。
2. **人工冒烟书源**：由 Agent 从阶段 0 语料中挑一个规则简单、纯 CSS、无登录的公开书源，只记录其 `bookSourceUrl` 的哈希与规则形态，不把书源内容提交进仓库。
3. **单元顺序**：Agent 自定；U1 / U3 / U5 文件不重叠可并行，U2 依赖 U1，U4 依赖 U2 + U3，U6 依赖 U1 + U3 + U5。

## 5. 风险

| 风险 | 缓解 |
| --- | --- |
| Kotlin 网络栈细节多（OkHttp 拦截器、重试、Cronet 开关），一次翻译不全 | U1 只做 `UrlOptions` 已定义的行为；未定义的按「解析保留、执行忽略」并记文档 |
| 字符集探测顺序猜错导致中文乱码 | U1 回源 `EncodingDetect` 与 `HttpHelper`，用 GBK 站点 fixture 测试 |
| WebBook 流程与 UI 状态耦合（进度回调、取消） | 以 async 函数 + `Task` 取消为边界，不引入回调 |
| 同模型复审盲区 | 下个会话 Opus@high 可用后，对 U1 与 U4 补交叉复审 |
