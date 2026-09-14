# 总结：阶段 2 数据与网络

## 开发项背景

阶段 1 的规则引擎全部离线：`java.*` 的网络方法是桩，没有真实 HTTP、Cookie、字符集解码，也没有书源实体、导入解析、书架与章节的持久化，引擎无法对着任何真实书源工作。本轮补齐这一层，并用真实数据（坚果云上的 Android 备份、公开书源）验证。

## 实现方案

六个单元，每个单元 Codex 实现、Codex 独立上下文复审、按 Kotlin 返修后提交（commit `e0bca04ae`、`a9b1d2503`、`236484452`）：

| 单元 | 内容 | 复审 finding |
| --- | --- | --- |
| U1 网络层 | `HttpClient` protocol、URLSession 实现（逐跳 Cookie、可控重定向）、`ReplayHttpClient`、字符集判定（去 BOM → 显式 → 响应头 → meta 含分号旧式 → UTF-8）、`CookieStore` actor（域名键按 OkHttp 公共后缀算法，PSL 静态表由 `tools/psl` 生成，MPL 2.0）、`UrlRequestBuilder`（CookieJar 两阶段、retry、UA `null` 哨兵） | 6 |
| U2 请求执行器与宿主网络方法 | `AnalyzeUrlExecutor`（内插、选项、限流、type、bodyJs、webView 桩）、`ajax` / `ajaxAll` / `connect` / `get` / `head` / `post` / `downloadFile` / `cacheFile` / `getCookie`、`CacheManager`、同步桥接的取消传播；响应对象以方法为主 | 6（5 修，1 条经回源确认 Kotlin 行为） |
| U3 实体与导入 | 15 个 Codable 模型 230 字段对齐 Kotlin 默认值；Gson 语义（缺失 / 显式 null / 转换失败三分、Int / Integer / Long 各自适配器）；书源与替换规则导入（旧字段映射、末尾竖线校验、`mainJs` 标记） | 6 + 真实数据 1 |
| U4 WebBook | 搜索 / 发现、详情、目录、正文四条流程与 `ContentProcessor`；精准搜索按 `checkKeyWord` + `precisionSearch` | 12 |
| U5 GRDB | 9 表 10 索引、Repository（书籍按 name+author 身份替换、章节 REPLACE、替换规则分组查询）、文件库挂起 / 恢复 | 3 |
| U6 备份与 WebDAV | 自实现 zip 读取器、按 Restore 顺序导入、WebDAV 客户端（PROPFIND / GET / exists / PUT / MKCOL）、下载 256 MiB 上限走有界客户端、只读冒烟工具 | 3 + 真实数据 1 |

**真实数据验证**：

- WebDAV 只读冒烟（坚果云测试账号，只发 PROPFIND / GET）：列出 711 个备份，最新一份导入 82 本书、4198 个书源、20 条替换规则、138 条阅读记录、154 个书签、9 个分组，无失败文件。真实包暴露并修复了两处缺陷：zip 读取器只调用一次 `compression_stream_process` 导致大条目误判损坏；实体词法解析对超长字符串用的 ICU 正则内部出错。
- 真实书源冒烟（`tools/webbook-smoke`，候选取自阶段 0 语料中纯 CSS、无登录的公开源）：逐浪小说完整跑通「搜索 1 条 → 详情 → 77 章目录 → 2 章正文（2084 / 1896 字）」。其余候选：轻之文库搜索与详情通过、目录超时；话本小说搜索与详情通过、目录为空；刺猬猫 / 维基阅读 / 纪念小说搜索无结果；不可能世界搜索 404。语料为 2024 年快照，站点变更与规则失效不可区分，未逐一定位。

工作区全量 274 项 XCTest 0 失败（冒烟工具另有 3 项）。补充文档：`docs/spec/network-compat.md`、`storage-notes.md`、`backup-notes.md`，`js-host-compat.md` 已更新失败语义对照表。

## 局限性

- 复审仍全部为 Codex 同模型独立上下文；Opus 交叉复审待项目级 agent 定义生效后补。
- `dnsIp` / 代理 / Cronet 选项解析保留、执行忽略；ICU 编码探测未实现；WebView / webJs 留桩。
- `replaceRule.previewText` 无配置存储，导入时记为已知丢失；`searchHistory` / `highlightRule` 等备份文件因缺实体与表而跳过。
- 替换规则的 `@js:` replacement 走同步 JS 引擎，超时不能抢占死循环脚本。
- 真实书源冒烟只有 1/8 完整通过，失败原因未定位（见上）。
- 工具链升到 swift-tools-version 6.1（GRDB 7.11.1 要求）。

## 后续 TODO

1. 阶段 3 SwiftUI MVP：书架、搜索、详情、目录、阅读器、书源管理、替换规则、设置、备份恢复；需要 Xcode 工程才能出 ipa。
2. 真实书源回归：对轻之文库目录超时与话本小说空目录做定位（抓取原始响应对比 Android 端）。
3. `searchHistory` / `highlightRule` / `previewText` 的实体、表与配置存储。
4. Opus 交叉复审阶段 1、2 全部单元。
