# iOS 适配计划

> 状态：**全部拍板**（2026-09-12，见 §7），阶段 0 已启动。
> 依据：三份子 agent 调研（架构盘点、规则引擎剖析、外部生态与选型），关键断言已由主会话抽查核实（2026-09-12）。

## 1. 结论先行

1. **两条可行路线，推荐纯 Swift 重写 + 跨平台一致性测试集**。KMP 共享内核在理论上能复用 3.5 到 4.5 万行 Kotlin，但四个关键依赖（jsoup、JsoupXpath、Rhino、OkHttp）在 Kotlin/Native 上全部不可用，替换后 Android 端也会被迫改动兼容性最敏感的路径；而无论哪条路线，JS 宿主层都要重写。
2. **真正的移植难点是 JS 宿主层，不是选择器**。书源脚本依赖约 103 个 `java.*` 宿主方法、Rhino 的 Java 对象包装语义、E4X、全局 CryptoJS 注入和 `let/const` 改写为 `var` 的老书源兼容逻辑。
3. **UI 无一行可复用**：`ui/` 占 10.2 万行（54%），全部是 View/XML，无 Compose。
4. **分发前提先于技术前提**：上游开发者因侵犯著作权罪获刑（媒体报道，判决书原文未核对），社区同类 iOS 应用「源阅读」「香色闺阁」均已从 App Store 下架，Apple 审核指南 5.2.2 要求「应请求提供第三方内容授权」。正式上架前景极差，现实分发路径是 TestFlight 或自签侧载。**这是方向性风险，人类已知情并决定继续（§7）。**

## 2. 现状盘点（来自仓库）

### 2.1 体量与耦合

| 包 | 行数 | Android 耦合文件占比 | 判定 |
| --- | ---: | ---: | --- |
| `ui` | 101,884 | 87% | 全部重写 |
| `help` | 25,183 | 47% | 混合，`help/book`、`help/coroutine`、`Highlight*`、`ReplaceAnalyzer` 可作规格参考 |
| `model` | 19,439 | 53% | 内核所在，`model/analyzeRule`（4,129 行）耦合仅 `@Keep`/`TextUtils`/`Base64` |
| `utils` | 12,331 | 73% | 深绑 |
| `service` | 7,823 | 71% | 深绑（10 个前台 Service） |
| `data` | 7,292 | 83% | 机械耦合（Room 注解），实体字段可直接作 schema 规格 |
| `modules/book` | 13,905 | 21/78 文件 | epublib fork，已 Android 化 |
| `modules/rhino` | 7,909 | 3 文件 | Rhino 外壳，iOS 不可用 |

来源：`app/src/main/java/io/legado/app/` 逐包 `wc -l` 与 `import android.` 统计。

### 2.2 规则引擎的兼容面（iOS 必须逐项对齐）

| 层 | Android 实现 | 兼容要点 |
| --- | --- | --- |
| 规则切分 | `RuleAnalyzer.kt`（377 行） | `&&` / `\|\|` / `%%` / `@` / 嵌套括号，纯逻辑，可逐行翻译 |
| 6 种模式 | `AnalyzeRule.kt:849` | `@CSS:` `@@` `@XPath:`（或 `/` 开头）`@Json:`（或 `$.` 开头）`<js>` / `@js:` `@webjs:` `{{ }}` `@get` / `@put` `##` 替换 `$1` 回填 |
| CSS 与私有语法 | `AnalyzeByJSoup.kt`（519 行）基于 jsoup **1.23.2，上游明确禁止升级**（`gradle/libs.versions.toml:53-56`） | `class.x.0`、`tag.div[-1:0]`、`text/textNodes/ownText/html/all` 末段关键字；iOS 用 SwiftSoup，需按 1.23.2 语义对拍 |
| XPath | JsoupXpath 2.5.3 | iOS 用 Kanna / Fuzi（libxml2），HTML5 解析树差异需用测试集暴露 |
| JSONPath | jayway json-path 3.0.0 | iOS 用 Sextant 或自研，注意非规范 JSON 的宽松解析（`AnalyzeUrl.kt:258-264`） |
| JS 宿主 | htmlunit-core-js（Rhino 分支）+ `JsExtensions`（77 方法）+ `JsEncodeUtils`（26 方法） | 见 §4.2 阶段 1 的分级实现 |
| 注入变量 | `AnalyzeRule.kt:897-911` 等 6 处 | `java` `cookie` `cache` `source` `book` `result` `baseUrl` `chapter` `src` `page` `key` 等 |
| URL 选项 | `AnalyzeUrl.kt:829-908` | `method` `charset` `headers` `body` `retry` `webView` `webJs` `timeout` `followRedirects` `dnsIp` `js` `bodyJs` 等 17 项 |
| 后处理 | `ContentProcessor.kt`、`ContentHelp.reSegment`（629 行）、`HtmlFormatter`、`ReplaceRule` | 替换规则含正则超时保护，繁简转换 |

### 2.3 数据层

Room 版本 111，26 个 Entity，25 个 DAO，39 条迁移。**不翻译迁移**：iOS 侧全新 schema，兼容层只做「导入 Legado 备份包」（JSON），与 Android 端通过 WebDAV 备份互通。

### 2.4 Android 系统能力在 iOS 的命运

| 能力 | iOS 结论 |
| --- | --- |
| 听书 TTS 后台 | 可对等：`UIBackgroundModes=audio` + AVSpeechSynthesizer / 在线 TTS |
| 前台 Service 批量缓存 / 下载 | 无等价物，改为前台任务 + URLSession background transfer |
| 局域网 Web 服务、MCP 服务 | 仅前台可用，退后台约 30 秒挂起。建议 MVP 砍掉 |
| WebView 无头抓取（`@webjs:`、`java.webView*`、`useWebView`） | 不可靠，须挂在 window 上零尺寸运行，仅前台。作为受限功能实现 |
| SAF 目录授权 | UIDocumentPicker + security-scoped bookmark，语义近似 |
| ContentProvider 对外 API、悬浮窗、应用内更新 | 删除 |

## 3. 路线对比

| 维度 | A. 纯 Swift 重写 + 一致性测试集（推荐） | B. KMP 共享内核 + SwiftUI | C. Compose Multiplatform 全量 | D. Flutter / RN |
| --- | --- | --- | --- | --- |
| 代码复用 | 0 行，但把 Kotlin 当规格逐行翻译 | 内核 3.5 到 4.5 万行理论可复用 | 同 B，UI 也重写 | 0 |
| 阻塞项 | 无库级阻塞，每类能力都有成熟 Swift 库 | XPath 在 KMP 侧**无可用库**（Ksoup 不做，xqt 停更于 2023）；jsoup → Ksoup 会改变 Android 端被钉死的 1.23.2 语义；Room → Room KMP 要求 DAO 全 suspend；OkHttp → Ktor Darwin 不支持代理 | 同 B，且 Android UI 10 万行也要重写 | JS 引擎嵌入更绕；官方 LegadoFlutter 2022 年停摆 |
| JS 层 | JavaScriptCore，宿主 API 用 Swift 重写 | JavaScriptCore（K/N 内置平台库）或 quickjs-kt，宿主 API 用 Kotlin 重写 | 同 B | 各自桥接 |
| 对 Android 端的影响 | 零 | 需把 Android 端迁到共享模块，等于重构一个活跃开发中的 19 万行工程 | 重写 | 零 |
| 长期同步成本 | 两套引擎靠测试集对齐，规则语义每次变更要改两处 | 一处改动两端生效 | 同 B | 两处 |
| 先例 | 所有能跑到 iOS 的社区移植（oilycn/legado-ios、LegadoReader-iOS、MetaRead）全部走此路线，但 star 均个位数，无可借力基座 | 无任何 KMP 移植先例；唯一的 CMP 项目 NovelReaderDual 因 Rhino 没有 iOS target | 无 | LegadoFlutter 已停 |

**推荐 A 的理由**：B 的省下的部分（选择器、模板解析、实体）恰恰是翻译成本最低的部分；B 多付的部分（改动 Android 端兼容路径、KMP 工具链风险、XPath 自研）是最贵的部分。A 用「一致性测试集」把 Kotlin 端当作可执行规格，复用发生在测试层而非代码层。**若团队长期打算让 Android 与 iOS 共用一份引擎且能接受 Android 端大重构，再考虑 B。**

## 4. 推荐路线的阶段划分

工期未估：团队人数、Swift 熟练度、投入比例未知（见 §6）。各阶段写清完成判据。

### 阶段 0 立项与规格化

- 本地新建 orphan 分支 `ios` 并搭建骨架；推送到远端属对外动作，须人类同意后执行。
- 建立 **一致性测试语料**：从 `app/src/test/java/io/legado/app/model/analyzeRule/` 的 6 个测试抽黄金用例；再按语法特征（纯 CSS、XPath、JSONPath、重 JS、登录、webView）**自造 HTML / JSON fixture** 离线跑，不发真实网络请求、不提交第三方站点内容（§7 语料合规）。每个用例记录 Android 端的输出作为期望值。
- 用同一批书源统计 JS 特性使用频率（`java.*` 各方法、E4X、`Packages.`、`new java.lang.String`、CryptoJS），产出「宿主 API 实现优先级表」。这决定阶段 1 的范围，不靠猜。
- 完成判据：语料仓库可在 Android 端一键跑出全绿基线。

### 阶段 1 规则引擎核心（Swift Package `LegadoCore`，无 UI）

- `RuleAnalyzer`、`AnalyzeRule` 六模式分派、`AnalyzeByJSoup` 私有语法、XPath、JSONPath、正则、`{{ }}` 内插、`@get/@put`、`##` 替换。
- `AnalyzeUrl` 选项解析（含宽松 JSON）与请求构造。
- JS 宿主（JavaScriptCore）：按阶段 0 的优先级表分三级实现。一级：网络请求、编码、加密、字符串、时间、`cookie` / `cache` 注入。二级：文件与压缩、字体反爬、并发控制、`importScript`。三级：`webView*`、`getVerificationCode`、Android 特有项（`androidId` 等，返回兼容占位）。
- 显式决策待实证：**Java 对象包装语义**（Rhino 下 `java.ajax()` 返回 `java.lang.String`，脚本可能写 `.length()`）与 **`let/const` 改写**是否在 JSC 上保留，各写一个最小实验进语料。E4X 不支持，按语料统计决定是否报错提示。
- TDD：本阶段全部是「输入 X 应得 Y」的纯逻辑，先写测试。
- 完成判据：一致性语料在 iOS 端通过率达到阶段 0 定义的阈值（建议一级书源 100%，整体 ≥ 90%）。

### 阶段 2 数据与网络

- GRDB 建新 schema，字段以 `data/entities/` 为规格，只建 MVP 需要的表（Book、BookGroup、BookSource、BookChapter、SearchBook、ReplaceRule、Cookie、Cache、ReadRecord、Bookmark）。
- Legado 备份包导入（书源、书架、替换规则、阅读进度），WebDAV 客户端。
- URLSession 封装：按源 headers / method / body / charset（含 GBK 解码）/ retry / followRedirects / timeout；`dnsIp` 在 iOS 无原生对应，文档标注为不支持。
- 完成判据：从一台 Android 设备的 WebDAV 备份恢复后，书架与书源在 iOS 端可用。

### 阶段 3 MVP UI（SwiftUI）

- 书架、搜索、发现、书籍详情、目录、阅读器、书源管理与导入（JSON / URL / 二维码）、替换规则、设置、备份恢复。
- 阅读器是第二大风险点：Android 端排版分页在 `ui/book/read/page/`（`ui/book` 共 5 万行）。iOS 用 CoreText 自建分页，先做纯文本正文，图片正文排后。
- UI 属 TDD 例外，先跑通再补测试。
- 完成判据：真机可完整走通「导入书源 → 搜索 → 加书架 → 阅读 → 进度同步」。

### 阶段 4 扩展（每项独立立项，按 §6 的范围拍板取舍）

TTS 听书（后台音频）、本地书籍（TXT 目录规则、EPUB、MOBI、PDF）、RSS、漫画与音频书源、`@webjs:` / `java.webView*`、段评、字典规则、书源编辑器、高亮与批注、局域网 Web 服务（前台限定）。

### 阶段 5 分发与 CI

- GitHub Actions `xcodebuild test` 跑 `LegadoCore` 单测与一致性语料。
- 分发已定为自签侧载：CI 产出未签名 `.ipa`，README 给 AltStore / Sideloadly 安装步骤；不做 TestFlight 与 App Store 提审流程。

## 5. 风险清单

| 风险 | 等级 | 缓解 |
| --- | --- | --- |
| 法律与分发：上游判例、同类应用下架、审核指南 5.2.2 / 2.5.2 | **方向性，已知情接受** | 不以上架为目标设计；分发限自签侧载 |
| JS 宿主兼容覆盖不足，社区书源大面积失效 | 高 | 阶段 0 用真实语料统计，按频率分级，不追求 103 个方法全量 |
| Rhino 特有语义（Java 对象包装、E4X、`let/const` 改写）在 JSC 上行为反转 | 高 | 阶段 1 先做最小实验，结论写回本文件 |
| jsoup 1.23.2 与 SwiftSoup、JsoupXpath 与 libxml2 的解析树差异 | 中 | 一致性语料专设「畸形 HTML」用例 |
| WebView 无头抓取在 iOS 不可靠 | 中 | 三级功能，仅前台，明确降级提示 |
| 后台任务受限（批量缓存、Web 服务） | 中 | MVP 砍 Web 服务，缓存改前台 + background transfer |
| 阅读器排版还原度 | 中 | 先文本后图片，参数（字距、行距、段距、缩进）对齐 Android 配置项 |
| 本仓库仍在活跃开发，规则语义持续变化 | 中 | 一致性语料随 Android 端 PR 同步更新，作为两端契约 |

## 6. 待确认项（只有人知道，不猜）

全部已拍板，见 §7。

## 7. 关键设计决策

| 决策 | 结论 | 含义 |
| --- | --- | --- |
| 是否继续 | **继续，接受法律与分发风险** | 人类已知悉 §1 第 4 条；后续 review 不再以此质疑方向 |
| 技术路线 | **A 纯 Swift 重写 + 一致性测试集** | SwiftUI + JavaScriptCore + SwiftSoup / Kanna + GRDB；Kotlin 端只作可执行规格，不改动 Android 工程 |
| 分发目标 | **自签侧载** | 不以过审为设计约束：后台模式按需声明、`@webjs:` 等灰区能力不必回避、无 4.7 小程序条款束缚；代价是免费账号 7 天续签、3 应用上限，需在 README 写清安装方式 |
| 仓库形态 | **本仓库 orphan 分支 `ios`**（人类已确认） | Swift 工程独占一棵树，不含 Android 代码；一致性语料引用 Kotlin 端时记录 `master` 的 commit hash |
| MVP 范围 | **接受 §4 阶段 3 边界**（人类授权 Agent 决定） | 网络文字书源 + 书架 + 搜索 / 发现 + 阅读器 + 替换规则 + 书源管理 + 备份恢复。阶段 4 优先级：TTS 听书 > 本地 TXT / EPUB > `@webjs:` 与 webView 抓取 > RSS > 其余 |
| 团队与工期 | **1 名人类 + Coding Agent，按阶段门禁推进，不设日历工期**（人类授权 Agent 决定） | 代码由子 agent 编写、主会话核验；每阶段以完成判据收口，不以日期收口 |
| 最低系统版本与设备 | **iOS 17，Universal（iPhone 优先布局，iPad 可用）**（人类授权 Agent 决定） | iOS 17 起 SwiftUI Observation 框架与 `NavigationStack` 稳定，GRDB / SwiftSoup / Kanna 均支持；iPad 只保证可用，不做专属布局 |
| 语料合规 | **仓库只提交合成 fixture 与聚合统计，不提交第三方站点抓取内容与整套书源合集** | 一致性测试用自造 HTML / JSON 覆盖同类语法特征；真实书源仅在本机缓存目录做频率统计，仓库记录合集来源 URL 与统计结果 |


## 8. 主要来源

- 仓库：`app/src/main/java/io/legado/app/model/analyzeRule/*`、`help/JsExtensions.kt`、`help/JsEncodeUtils.kt`、`modules/rhino/src/main/java/com/script/rhino/RhinoContext.kt`、`data/AppDatabase.kt`、`gradle/libs.versions.toml`、`app/src/main/AndroidManifest.xml`。
- 上游状态：https://github.com/gedoor/legado （2026-09-12 经 GitHub API 核实仅剩 README 与公告图片，Issues 关闭）。
- 判例报道（媒体，未核对判决书）：https://www.landian.news/archives/113119.html 、https://meta.appinn.net/t/topic/83164
- Apple 审核指南：https://developer.apple.com/app-store/review/guidelines/ （5.2.1、5.2.2、2.5.2、4.7）。
- KMP 成熟度：https://kotlinlang.org/docs/multiplatform/supported-platforms.html 、https://developer.android.com/kotlin/multiplatform/room 、https://ktor.io/docs/client-engines.html
- Ksoup 无 XPath：https://github.com/fleeksoft/ksoup/issues/109 （经核实仍 open）。
- K/N 内置 JavaScriptCore：https://github.com/JetBrains/kotlin/tree/master/kotlin-native/platformLibs/src/platform/ios （经核实存在 JavaScriptCore.def）。
- 社区 iOS 移植：https://github.com/oilycn/legado-ios 、https://github.com/tomcat117853/LegadoReader-iOS 、https://github.com/hankdab/MetaRead 、https://github.com/gedoor/LegadoFlutter
- iOS 后台与 WebView 限制：https://developer.apple.com/forums/thread/685525 、https://developer.apple.com/forums/thread/714946
