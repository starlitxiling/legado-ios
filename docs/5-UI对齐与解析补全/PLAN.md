# 轮次 5 计划：UI 对齐原版 + 解析管线补全

> 状态：人类已确认（2026-09-18），六项决策全部按「都做」定案（见 §8）。由 Codex 按本文单元逐个执行，做完一批接着做下一批，不停下等指令。
> 规格基线：Kotlin `2bdd3c58b`（实测上游 `model/`、`help/`、`modules/` 目录至今无新提交，规格不过期）。
> 路径约定：Android `app/src/main/java/io/legado/app/` 简写 **K/**，Android 资源 `app/src/main/res/` 简写 **R/**，`app/src/main/assets/` 简写 **A/**；iOS 核心库 `Packages/LegadoCore/Sources/LegadoCore/` 简写 **C/**，iOS 应用 `App/Sources/` 简写 **S/**。行号取自 2026-09-18 的工作树，执行前以实际文件为准。

## 0. 现状与本轮定位

| 指标 | 值 | 备注 |
| --- | --- | --- |
| `ios` 分支 HEAD | `30d180ecf` | 工作树另有 23 个文件未提交（轮次 4 真机修复，见 §2） |
| LegadoCore 源码 | 约 30,000 行 Swift | 规则引擎、网络、WebBook、本地书、备份、存储 |
| App 源码 | 约 10,950 行 SwiftUI | 最大文件 `ReaderView.swift` 459 行、`BookshelfView.swift` 237 行 |
| LegadoCore 单测 | 549 项，1 失败 | 失败项 `MobiPdfTests.swift:78`（PDF 分组标题） |
| 一致性语料 | 134 / 142 | 8 条 unsupported 全是运行器不支持替换预览，非引擎缺陷 |
| JS 宿主 `java.*` | Kotlin 104 个，Swift 约 34 个 | 缺 70 个，含一级方法 `toast` |
| 本地书格式 | txt / epub / mobi / azw3 / pdf | 缺 umd、azw、zip / rar / 7z 压缩包 |
| 真实书源回归 | 8 个候选只有 1 个端到端通过 | `docs/HANDOFF.md:111` |
| 真机整架更新 | 47 本中 14 成功 / 33 失败 | 24 本缺书源、9 本超时或解析失败 |

**一句话定位**：四轮下来功能面已铺全，但深度不够 —— 规则引擎有 6 条已知 P0 未修、JS 宿主缺三分之二方法、本地书缺整类格式、UI 是薄壳。本轮不再横向铺新功能，而是**纵向对齐**：解析线以 Kotlin 为可执行规格逐项对拍，UI 线以 Android 原版布局尺寸配色为规格逐屏复刻。

## 1. 范围

**做**：§3 解析线 P0–P9 全部单元、§4 UI 线 U0–U9 全部单元、§5 真实回归。
**不做**：书源类型 3 / 4；应用内更新、悬浮窗、Quick Settings Tile、ContentProvider；`@webjs:`（语料使用率 0%）、E4X（0%）、`%%` 组合的进一步打磨（0.27%）；`barElevation` / `transparentStatusBar` / `bottomBarSkin` 三项主题键（iOS 无对应视觉）。

## 2. 单元 P0：先落地未提交的真机修复

工作树里的 23 个文件是轮次 4 的真机修复集（启动流程改 `UIApplicationDelegateAdaptor`、规则引擎与 JS 引擎加 `autoreleasepool` 解决 OOM、新增 `BackupAES.swift` 接入加密备份项、`JavaHost` 补 `digestHex` 五种摘要、新增 `tools/backup-import-check` 与 `tools/conformance-run`）。测试已配套，只差 commit。

1. 修掉 `MobiPdfTests.swift:78` 的红：PDF 分组标题应为「第 1–2 页」形态还是「全书」，以 Kotlin `K/model/localBook/PdfFile.kt:34,217-233`（`PAGE_SIZE=10` 固定分段，标题格式）为准改实现或改断言。
2. 全量单测绿后按内容拆成 2–3 个 commit（启动与内存 / 备份加密 / 校验工具），message 描述最终状态。
3. 补 `docs/4-收尾与真机验证/SUMMARY.md`（四段式），把 `PROGRESS.md` 里已完成项移入。

**验收**：`git status` 干净；549 项单测 0 失败。

## 3. 解析线（P 系列）

每个单元的写法：**规格**（Kotlin 位置与行为）→ **现状**（iOS 位置与差异证据）→ **改动**→ **测试用例**（TDD，先写红）→ **验收**。凡是能写出「输入 X 得到输出 Y」的都先写测试；对拍用例直接从 Kotlin 行为推导，放进 `Packages/LegadoCore/Tests/LegadoCoreTests/`，语料型用例追加到 `Tests/Conformance/`。

### P1 AnalyzeRule 六条 P0 / P1（接续轮次 4 的 C7）

来源：`docs/4-收尾与真机验证/REVIEW.md:11-31`，全部是**静默返回不同结果**的缺陷，语料里 `&&` 占 37.6%、`||` 占 27.2%。

| # | 缺陷 | 规格 | 现状 | 改动 |
| --- | --- | --- | --- | --- |
| 1 | 组合符被切两次 | `K/model/analyzeRule/RuleAnalyzer.kt:191` 与 `AnalyzeByJSoup.kt:90`：分派层切完 `\|\|` 后 jsoup 层不再切。`@CSS:p@text&&p@id\|\|x` 得 `A` | `C/AnalyzeRule/AnalyzeRule.swift:237,251` 切一次，`C/AnalyzeByJSoup/AnalyzeByJSoup.swift:71` 又切一次，得 `A\nB` | jsoup 层只接收已切好的单段；组合逻辑只在 AnalyzeRule 层 |
| 2 | 映射内容缺「按键直取」 | `AnalyzeRule.kt:220-245,321-337`：内容是 `NativeObject` / `LinkedTreeMap` 时只取首段规则、按键直取 | `AnalyzeRule.swift:175-204` 无此分支，字典被丢给 jsoup | 增加 content 为字典 / JS 对象的分支，返回 `content[rule]` 的字符串化 |
| 3 | `isUrl` 末处理 | `AnalyzeRule.kt:277-292,347-383`：isUrl 时 Default 段取列表首项，空则回 `baseUrl`，否则按 `redirectUrl` 绝对化并去重 | `AnalyzeRule.swift:207-209` 只取首项；绝对化外移到 `C/WebBook/WebBook.swift:246-249,299-304` 且多一条 `url != base` 过滤 | 把绝对化收回 AnalyzeRule；补 `setBaseUrl` / `setRedirectUrl`（`AnalyzeRule.kt:118-134`，data URL 不覆盖）；删掉 WebBook 层的额外过滤 |
| 4 | `getStringList` 无 `isUrl` 形参 | `AnalyzeRule.kt:347` | `AnalyzeRule.swift:118-122` | 补形参并走同一末处理 |
| 5 | CSS 空片段不抛 | `AnalyzeByJSoup.kt:91`：`@CSS:p@text&&` 抛异常 | `C/AnalyzeRule/SelectorEngine.swift:26`、`AnalyzeByJSoup.swift:69` 返回 `data()` 继续 | 抛错，错误文案对齐 |
| 6 | 空结果集区间索引吞异常 | `AnalyzeByJSoup.kt:348,354,391`：无 `li` 时 `tag.li[0:-1]` 抛 | `C/AnalyzeByJSoup/JSoupIndex.swift:89` 提前返回空 | 抛错 |
| 7 | `setContent(nil)` | `AnalyzeRule.kt:104-116`：抛 AssertionError 并重置 XPath / JSoup / JSonPath 三缓存 | `AnalyzeRule.swift:38-43` 只重置 jsoup 缓存、nil 不抛 | 三缓存同步重置；nil 抛错 |

**测试**：每条一个 `testKotlin*` 对拍用例（沿用 `RuleAnalyzerTests.swift` 的命名）；用例 1 至少覆盖 `&&` 内含 `\|\|`、`\|\|` 内含 `&&`、三段以上混合各一条。
**验收**：7 条用例绿；一致性语料不回退（仍 ≥ 134 / 142）。

### P2 `@js:` 上下文对象与 URL 脚本宿主

**规格**：`AnalyzeRule.kt:896-915` 注入 `java / cookie / cache / source / book / result / baseUrl / chapter / chapters / title / src / nextChapterUrl / rssArticle / fromBookInfo`，`book` / `chapter` / `source` 是完整实体（脚本常读 `book.name`、`book.author`、`chapter.index`、`chapter.title`、`source.bookSourceUrl`、`source.header`）。`AnalyzeUrl.kt:426-448`：URL 脚本里 `java.put / java.get` 读写章节变量与 `infoMap`。

**现状**：`C/AnalyzeRule/AnalyzeRule.swift:49-59` 只填 `src / book / chapter / source / title`，且实体只有 `{name:}` 骨架；`chapters / nextChapterUrl / rssArticle / fromBookInfo` 恒 NSNull。`C/JsEngine/JsEngine.swift:158-167` 的 URL 会话不传 parser，`C/JsEngine/JavaHost.swift:177-184` 的 `analyzer()` 必抛「未实现：java.get/put」；`infoMap` 注入裸对象，`infoMap.get(k)` 为 undefined（`JsEngine.swift:108,162-165,177`）。

**改动**：
1. 定义 `JsBookBinding / JsChapterBinding / JsSourceBinding`，把实体全字段（含 `variable` 里的 JSON 变量）以只读对象注入；`source` 另挂 `getVariable / setVariable / getKey / getLoginHeader / getLoginInfo`。
2. `chapters`（目录数组）、`nextChapterUrl`、`fromBookInfo`（Bool）按调用点传入；`rssArticle` 在 RSS 流程传入。
3. URL 会话持有 parser，`java.put / java.get` 走同一条 put / get 链（`AnalyzeRule.kt:856-890` 的 chapter→book→ruleData→source 顺序）；`infoMap` 以 `javaMapBindings` 注入使 `.get()` 可用。

**测试**：脚本 `book.author + '|' + chapter.index + '|' + source.bookSourceUrl` 返回期望串；searchUrl 内 `java.put('k','v')` 后 tocUrl 内 `java.get('k')` 得 `v`；`infoMap.get('page')` 得当前页。
**验收**：以上用例绿；一致性语料 `js` 组不回退。

### P3 JS 宿主 API 补全

**规格**：`K/help/JsExtensions.kt`（104 个方法）与 `K/help/JsEncodeUtils.kt`（33 个加解密）；使用率来自 `docs/0-iOS适配规划/宿主API优先级.md`。
**现状**：`C/JsEngine/JavaHost.swift:112-116` 白名单 35 项，`:282 default: throw unimplemented`。`toast` 在白名单里但 switch 无 case，脚本一调就整条规则中断。

按组交付，每组一个 commit：

| 组 | 方法 | 要点 |
| --- | --- | --- |
| 3a UI 与系统 | `toast` `longToast` `logType` `randomUUID` `androidId` `getReadBookConfig` `getThemeMode` `getThemeConfig` | toast 走宿主注入的回调（App 层用 overlay 提示），Core 层测试用假回调；`androidId` 返回 `identifierForVendor` |
| 3b 编解码 | `base64DecodeToByteArray` `hexDecodeToByteArray` `hexEncodeToString` `strToBytes` `bytesToStr` `decodeURI` `htmlFormat` `toURL` | **前置**：`JavaHost.bridge`（`JavaHost.swift:148-160`）增加 ByteArray 桥（JS 侧 `Uint8Array` / Java 风格数组互转），否则 3c、3e 无法做 |
| 3c 加解密 | `md5Encode16` `HMacHex` `HMacBase64` `digestBase64Str` `createSymmetricCrypto`×4 `createAsymmetricCrypto` `createSign` `aes*`（12）`des*`（4）`tripleDES*`（4） | `createSymmetricCrypto` 返回可链式调用对象（`JsEncodeUtils.kt:45-75`）；用 CryptoKit + CommonCrypto，新建 `C/JsEngine/JavaHostCrypto.swift` |
| 3d 时间 | `timeFormatUTC`；`timeFormat` 补自定义格式重载 | 与 Android 同用 `yyyy/MM/dd HH:mm` 默认 |
| 3e 文件与压缩 | `getFile` `readFile` `readTxtFile`×2 `deleteFile` `unzipFile` `un7zFile` `unrarFile` `unArchiveFile` `getTxtInFolder` `get{Zip,Rar,7z}{String,ByteArray}Content` `importScript` | 与 P7 共用压缩库（见 §6 决策）；`importScript` 支持 http / 本地 / 缓存三来源 |
| 3f 缓存 | `cache.getByteArray / putFile / getFile / putMemory / getFromMemory / deleteMemory` | 接入现有 `CacheManager` |
| 3g 字体 | `queryBase64TTF` `queryTTF` `replaceFont` | 移植 `K/lib/QueryTTF.java`（glyf 表解析）；可后置到批次 4 |
| 3h 书籍与并发 | `getSource` `getTag` `refreshBookInfo / BookToc / Content` `cacheContent` `singleFlight` `lock` `tick` `openUrl` | `refresh*` 依赖 P4 缓存接线 |

**Rhino 兼容项**（`docs/spec/js-host-compat.md:9-11`）：注入 CryptoJS（书源常 `importScript` 后直接用）；`let / const` 归一化不做，JSC 原生支持；`String.length()` 调用形态用 Proxy 兜底不做，记入 compat 文档。

**测试**：每个方法至少一条与 Android 输出逐字对拍的用例（加解密用固定密钥与向量）；`toast` 用例断言回调收到文案且脚本继续执行。
**验收**：`宿主API优先级.md` 一级 16 个、二级全部方法均有实现；白名单与 switch case 一一对应（加一条测试枚举白名单逐个调用，不得落到 default）。

### P4 WebBook 四流程补全

| # | 能力 | 规格 | 现状 | 改动 |
| --- | --- | --- | --- | --- |
| 1 | `loginCheckJs` 包裹响应 | `K/model/webBook/WebBook.kt:77-101`：搜索 / 发现 / 详情 / 目录 / 正文五处入口均包裹，含错误响应二次判定 | WebBook 目录零命中；Rss / HttpTTS / SourceLogin 已有实现 | 在 `WebBookContext.request` 统一包裹，复用现成实现 |
| 2 | `infoHtml` / `tocHtml` 复用 | `BookList.kt:76,134`、`WebBook.kt:212-220,312-320,436-446`：搜索页即详情页时省一次请求 | 整个 Core 无 `infoHtml` | `SearchBook` / `Book` 增字段；详情与目录流程优先用缓存 HTML |
| 3 | 正文缓存与图片落盘 | `WebBook.kt:402-409,496-507`：取正文先读缓存，之后 `saveContent` 并回读；`BookHelp.kt:485-495` `saveImages` | `C/Cache/BookHelp.saveContent` 无调用方；`C/Cache/BookImages.saveImages` 无调用方 | 在 `BookContent.load` 后接线；阅读器与「缓存全本」走同一读路径 |
| 4 | 目录 / 正文多页并发 | `BookChapterList.kt:99-119`、`BookContent.kt:106-130`：`mapAsync(threadCount)` | `C/WebBook/BookChapterList.swift:32-38`、`BookContent.swift:57-64` 串行 | `withThrowingTaskGroup` 限并发 `threadCount`，结果按序拼接 |
| 5 | `webJs` / `sourceRegex` 对所有类型放开 | `WebBook.kt:458-460` | `BookContent.swift:33-36` 非媒体书直接抛 | 删掉类型判断 |
| 6 | `subContent` 副文 / `contentBatch` 批量正文 | `BookContent.kt:131-168,283-332` | 只有字段定义 | 实现；`contentBatch` 依赖 3h 的 `cacheContent` |
| 7 | `adaptSpecialStyle` 的 `<usehtml>` 占位保护 | `BookContent.kt:243-259` | 缺 | 格式化前挖坑、后回填 |
| 8 | 去重粒度 | 搜索 `LinkedHashSet(SearchBook)` 全字段（`BookList.kt:142`）；目录全字段（`BookChapterList.kt:124-133`） | 搜索只按 `bookUrl`、目录只按 `url` | 改成全字段 Hashable |
| 9 | 详情页项 `bookUrl` 来源 | `BookList.kt:165-169`：`isRedirect ? baseUrl : absolute(analyzeUrl.url, ruleUrl)` | `BookList.swift:29` 恒用 baseURL | 传入 `isRedirect` |
| 10 | 多源合并与 precision 四档排序 | `K/model/webBook/SearchModel.kt:153-233` | 只在 `S/Features/WebService/WebSocketSearch.swift:126-144` | 下沉到 `C/WebBook/SearchModel.swift`，App 搜索页与 Web 服务共用 |
| 11 | `shouldBreak` / `preciseSearch` / `upChapterInfo` / `simulatedTotalChapterNum` | `BookList.kt:138-140`、`WebBook.kt:556-575`、`BookChapterList.kt:309-329` | 缺 | 实现 |
| 12 | `isOnLineTxt` 全角缩进 | `BookContent.kt:169-178` | 缺 | 实现 |
| 13 | 纯 JS 书源 `payAction` | `WebBook.swift:135` 硬编码 nil | — | 对齐常规分支 |
| 14 | `java.reGetBook` / `refreshTocUrl` / `getElementsRaw` | `AnalyzeRule.kt:422-449,985-1024` | 缺 | 实现 |

**测试**：用 `WebBookParityTests.swift` 的假 HTTP 客户端写每条对拍用例；缓存接线用例断言第二次取正文不发请求；并发用例断言乱序返回仍按页序拼接。
**验收**：用例绿；§5 真实书源回归 8 个候选 ≥ 6 个端到端通过。

### P5 内容净化

| # | 能力 | 规格 | 现状 | 改动 |
| --- | --- | --- | --- | --- |
| 1 | 简繁转换 | `K/help/book/ContentProcessor.kt:153-163`、`BookChapter.kt:136-141`：`chineseConverterType` 1→t2s、2→s2t，正文与标题都转 | 整链缺失，连配置项都没有 | 新建 `C/Content/ChineseConverter.swift`（词表见 §6 决策）；接入 `ContentProcessor.swift:82` 与 `title()`；配置项进 `AppPreferences`；同时提供 `java.t2s / s2t` |
| 2 | `reSegment` 重新分段 | `ContentProcessor.kt:149-152` → `K/help/book/ContentHelp.reSegment` | `ContentProcessor.swift:82` 只有注释 | 移植 `ContentHelp` |
| 3 | `<usehtml>` 占位保护 | `ContentProcessor.kt:164-171,208-210` | 缺 | 同 P4-7 |
| 4 | `scopeSource` 书源级净化 | `K/data/dao/ReplaceRuleDao.kt:117-121` | 字段在，`applies()` 不消费 | Repository 增查询；`ContentProcessor.swift:117-123` 消费 |
| 5 | `removeSameTitleCache` | `ContentProcessor.kt:65,83-90,125` | 缺，已缓存章节会重复截断 | 实现 |
| 6 | `replaceEnabled` 默认 | `K/data/entities/Book.kt:232-238`：config 为 null 回落全局默认，图片源与本地 epub 默认关 | `ContentProcessor.swift:47,83` 只判 `!= false` | 补全局默认与两条分支 |
| 7 | 处理器池与规则热更新 | `ContentProcessor.kt:39-81` | 构造时注入 | 按 book 缓存 + `upReplaceRules()` |

**测试**：t2s / s2t 用 20 组常见词对拍（含「后 / 後」「发 / 髮」这类一对多，以 Android 所用 HanLP / OpenCC 词表输出为准，取原文核对后再写断言）；`reSegment` 用 Kotlin 测试里的样本。

### P6 网络层

| # | 能力 | 规格 | 现状 | 改动 |
| --- | --- | --- | --- | --- |
| 1 | `proxy` | `AnalyzeUrl.kt:141-146,638-640`：从 header 取 `proxy` 并移出 headerMap，据此选客户端（socks / http） | `C/Network/UrlRequestBuilder.swift:20` 静默丢弃 | `URLSessionConfiguration.connectionProxyDictionary` 按 proxy 串构造；同 proxy 复用 session |
| 2 | `dnsIp` / `resolveIp` | `K/help/http/NetworkOptions.kt:42-72` | `C/AnalyzeUrl/UrlOptions.swift:81-118` 只解析不生效 | 通过 host 替换 + `Host` 头 + SNI（`URLSession` 无自定义 DNS，采用「IP 直连 + Host 头」方案，记入 `network-compat.md`） |
| 3 | `customHosts`（轮次 4 C2） | `K/help/config/AppConfig` + OkHttp Dns | 只存偏好 | 与 2 共用同一 host 映射层 |
| 4 | `CustomUrl` / `upload()` multipart | `K/model/analyzeRule/CustomUrl.kt:12-47`、`AnalyzeUrl.kt:731-750` | 缺 | 实现 |
| 5 | 分页 `<a,b,c>` | `AnalyzeUrl.kt:233-245`：`pagePattern="<(.*?)>"`，不校验 page | `C/AnalyzeUrl/AnalyzeUrlExecutor.swift:55-63` 正则不同且多一条 `page>0` 抛错 | 对齐正则与越界行为 |
| 6 | `origin` / `serverID` 消费 | `AnalyzeUrl.kt:297,906` | 只打日志 | `origin` 供加书架取来源；`serverID` 供 WebDAV 凭据选择 |

**测试**：环境是被测行为的输入 —— 代理与 DNS 用例不得真发网络，用协议化的假 session 断言构造出的请求 host / 头 / 代理字典。

### P7 本地书

**入口白名单**：`C/LocalBook/LocalBook.swift:34` 与 `S/Features/LocalImport/LocalImportView.swift:49` 改为 Android 的 `bookFileRegex`（`K/constant/AppPattern.kt:43`：txt / epub / umd / pdf / mobi / azw3 / azw）+ 压缩包 `archiveFileRegex`（`AppPattern.kt:47`：zip / rar / 7z）。

| # | 能力 | 规格 | 现状 | 改动 |
| --- | --- | --- | --- | --- |
| 1 | **UMD** | `K/model/localBook/UmdFile.kt:96-127`：读 header 取书名 / 作者 / 类型，按 `chapters.titles` 建目录，正文 zlib 解压 | 全缺 | 新建 `C/LocalBook/UmdFile.swift`，移植 `modules/book` 的 UMD 读取器 |
| 2 | **压缩包导入** | `LocalBook.kt:410-423`、`K/utils/ArchiveUtils.kt:94-101`：解包后按 `bookFileRegex` 逐个导入 | 全缺（`ZipReader.swift` 只服务 EPUB） | zip 用现有 `ZipReader` 扩展；rar / 7z 见 §6 决策 |
| 3 | **TXT 目录规则打分** | `K/model/localBook/TextFile.kt:497-534`：间隔 >1000 字计 csNum、<100 字计 numE（卷），`csNum >= numE*3 && csNum > maxNum + overRuleCount` 才换规则，`maxNum > 70` 提前 break | `C/LocalBook/TextFileParser.swift:74-81` 只比匹配数 | 逐行移植打分 |
| 4 | TXT 长章拆分 / 分卷 | `TextFile.kt:71,214-219,369-375`：`maxLengthWithToc=102400`，超长章标 `isVolume` 续写子章 | 缺 | 实现 |
| 5 | TXT 规则 JS replacement | `TextFile.kt:539-590`：注入 `result / book / index / prevTitle / prevLength / lastVolumeTitle / java`，`java.putVolume()` 可插卷 | 只做正则模板替换 | 接 JsEngine |
| 6 | charset 与选中规则持久化 | `TextFile.kt:91-104`：`book.charset` 空或文件改动才重测；选中规则存 `book.tocUrl` | 每次重测重选 | 持久化；`isLocalModified()`（`K/data/entities/BookExtensions.kt:311`）触发重解析 |
| 7 | 编码采样与检测器 | `TextFile.kt:65`：采样 512000 字节；`K/help/EncodingDetect.kt` 用 ICU 26 个识别器；`getHtmlEncode` 解析 meta charset | 采样 64KB；只做 BOM + UTF-16 启发 + GB / Big5 频率 | 采样对齐；识别器补 Shift_JIS、EUC-JP、EUC-KR、windows-1251 / 1252、ISO-8859-1 的统计识别；补 meta charset |
| 8 | TXT 章节 url | `TextFile.kt:112-114`：`md5Encode16(originName + index + title)` | `"txt:\(index)"` | 对齐（否则跨端备份互导时章节 url 不一致） |
| 9 | 文件名解析用户 JS | `LocalBook.kt:460-476`：`bookImportFileName` 用户脚本优先 | 缺 | 实现 |
| 10 | **EPUB 多级目录** | `modules/book` 的 `EpubTocNode(id, parentId, depth, title, href)` | `C/LocalBook/EpubParser.swift:39` 无层级 | 目录节点带 depth；目录页可折叠（U6） |
| 11 | **EPUB / MOBI 正文图片** | `K/model/localBook/EpubFile.kt:281-299`：保留 `<img>`，`image→img`、`xlink:href→src`、相对路径 resolve，`getImage(href)` 供流 | `EpubParser.swift:134-138`、`C/LocalBook/MobiFile.swift:43-45` 替换成「[图片]」 | 保留 img，注册本地图片提供者给阅读器 |
| 12 | EPUB script / style 剥离与 titlepage 特判 | `EpubFile.kt:230-249` | 不剥 | 对齐 |
| 13 | EPUB 封面路径 | `EpubFile.kt:300-322`：`covers/<md5(bookUrl)>.jpg` | 书目录下 `cover` | 对齐 |
| 14 | **PDF 形态** | `PdfFile.kt:179-214`：渲染成位图，正文只输出 `<img src="页号">` | `C/LocalBook/PdfFile.swift:65-71` 抽文本，扫描版 PDF 正文全空 | 改为 PDFKit 渲染页图 + `<img>`；大纲 `PdfOutline` 供目录树 |
| 15 | MOBI 复核 | `K/model/localBook/MobiFile.kt:99-282` KF6 + KF8 | `MobiFile.swift` 48 行壳 + `Mobi/` 解码器 | 逐段对照，补图片与多级目录 |
| 16 | **导入入口** | `LocalBook.kt:425 importFiles(uris)`、`importFileOnLine`、`K/model/remote/RemoteBook` | 只有 Files 单入口 | ① `App/project.yml` 加 `CFBundleDocumentTypes` / `LSSupportsOpeningDocumentsInPlace` / `UIFileSharingEnabled`，支持「用 Legado 打开」与 iTunes 文件共享；② `onOpenURL` 接收分享；③ 扫描目录（security-scoped bookmark 持久化）；④ WebDAV 远端书库浏览导入（复用 `WebDavLocalBookRestore`）；⑤ 添加网址（`importFileOnLine`） |

**测试 fixture**：新增 `Tests/Fixtures/localbook/`：GBK TXT、UTF-16 TXT、Shift_JIS TXT、带卷标题 TXT（打分用例）、多级目录 EPUB、带图 EPUB、UMD、扫描版 PDF、zip 包含两本 TXT。UMD 与 Shift_JIS fixture 若无现成样本由脚本合成。
**验收**：白名单 10 种扩展名全部可导入并阅读；TXT 打分用例与 Kotlin 选出同一条规则。

### P8 书架与缓存

| # | 能力 | 规格 | 现状 | 改动 |
| --- | --- | --- | --- | --- |
| 1 | 加书架置顶 | `K/ui/book/info/BookInfoViewModel.kt:489-505,542`：`order = minOrder - 1` | `S/Features/BookDetail/` 无 `order` 处理 | 实现 |
| 2 | 本地 TXT 缓存判定 | `K/help/book/BookHelp.kt:631-645`：本地 TXT 直接 true | `C/Cache/BookHelp.swift:43-46` 丢了该分支 | 补 |
| 3 | `clearInvalidCache` | `BookHelp.kt:171-201` | 缺 | 实现 + 设置页入口 |
| 4 | 更新检查 10 分钟节流 | `K/model/ReadBook.kt:1785` | 记了 `lastCheckTime` 无消费者 | 消费 |
| 5 | `latestChapterTitle` 模拟阅读 | `BookExtensions.kt:386-394` | 恒取末章 | 对齐 |
| 6 | 改名后缓存迁移 | `BookHelp.kt:151-168` | 读时扫描历史目录 | 可保留现方案，记入 `storage-notes.md` |
| 7 | 整架更新失败归因 | 真机 33 本失败 | — | 更新结果面板按「缺书源 / 超时 / 解析失败」分类展示，缺书源的给「换源」入口 |

### P9 JSONPath 与 XPath

| # | 能力 | 规格 | 现状 | 改动 |
| --- | --- | --- | --- | --- |
| 1 | 大整数精度 | json-smart 溢出升 BigInteger | `C/AnalyzeByJSonPath/JsonPathJSON.swift:122-124` 超 Int64 走 Double | 超范围整数保留原文本 |
| 2 | 过滤运算符 | Jayway `contains / subsetof / anyof / noneof` | `JsonPathPredicate.swift:147` 仅 11 项 | 补 4 项 |
| 3 | 函数 | `avg / stddev / size() / keys / concat / append / index` | `JsonPathEvaluator.swift:99` 抛 | 补 |
| 4 | XPath `tidyText()` | JsoupXpath 私有 NodeTest | 白名单外抛错 | 补 |
| 5 | **XPath 自研求值器** | JsoupXpath 在 jsoup 树求值 | libxml2 桥接：祖先轴丢失、tbody 补全反向、HTML5 实体不解码（`docs/spec/xpath-compat.md:6-27`），单点修补无效 | 在 SwiftSoup DOM 上实现 XPath 1.0 子集 + JsoupXpath 扩展函数（可嵌谓词）；旧桥接保留为 fallback 开关直至语料全绿 |
| 6 | C5b 复审 | 轮次 4 未开审 | — | 5 完成后派只读复审 |

**验收**：`xpath-compat.md` 三条硬差异对应用例全部翻绿；JSONPath 一致性语料不回退。

## 4. UI 线（U 系列）

### 4.0 总体风格约定（所有 U 单元共同遵守）

**目标一句话**：看起来像 Android 版 Legado，摸起来像 iOS 应用。布局、层级、尺寸、配色、文案、菜单项**照抄原版**；控件用 SwiftUI 原生（`List`、`TabView`、`NavigationStack`、`Slider`、`Toggle`、`Menu`），不模拟 Material 波纹、不画 Android 阴影，导航返回用系统手势。

| 约定 | 值 | 依据 |
| --- | --- | --- |
| 尺寸换算 | dp → pt 按 1:1，sp → pt 按 1:1 | 两端逻辑像素密度一致 |
| 字号 | 正文 14、中 16、大 18；列表标题 16、副文 13、网格书名 12、菜单 16 | `R/values/dimens.xml`、各 item 布局 |
| 边距 | 页面左右 16；列表项 padding 16；书架网格 item 间距 12（首末行 +24） | `dimens.xml`、`AppConfig.bookshelfMargin` |
| 圆角 | 卡片与按钮 8；小胶囊标签 3；搜索框 35（胶囊）；封面 12（网格）；配色圆块直径 48 | `R/drawable/*.xml` 统计 |
| 分割线 | 0.5pt，色 `#66666666`（夜 `#363636`） | `styles.xml Style.Line` |
| 顶部进度 | 2pt 细条贴导航栏下沿（搜索 / 详情 / 换源 / 导入页） | `RefreshProgressBar` |
| 图标 | SF Symbols，映射表见 U9；底栏图标 24pt | `R/menu/main_bnv.xml` |
| 深色 | 跟随 `ThemeStore.mode`，四态：跟随系统 / 亮 / 暗 / E-Ink | `R/values-zh/arrays.xml theme_mode` |
| E-Ink | elevation 0、无过渡动画、翻页动画强制「无」、菜单不淡入 | `K/help/config/AppConfig.kt:50,455` |
| 文案 | 全部取 `R/values-zh/strings.xml` 原文（书架 / 发现 / 订阅 / 我的、目录 / 朗读 / 界面 / 设置……） | — |
| 空态 | 各页一行居中灰字（原版无统一插画） | `fragment_explore.xml:37` |
| 加载态 | 居中 48pt 转圈 + 上边距 16 的「加载中」 | `view_loading.xml` |

### U0 主题系统（其余 U 单元的前置）

**规格**：`K/help/config/ThemeConfig.kt` + `A/defaultData/themeConfig.json`：四个色槽 primary / accent / background / bottomBackground，日夜各一套；4 个内置预设；用户可改色、可保存自定义主题。E-Ink 为第四种模式。
**现状**：`S/Shared/Theme.swift` 14 行，只有一个写死的墨绿 accent。

| 预设 | 夜间 | primary | accent | background | bottomBackground |
| --- | --- | --- | --- | --- | --- |
| 默认 | 否 | `#795548` | `#E53935` | `#F5F5F5` | `#EEEEEE` |
| 典雅蓝 | 否 | `#03A9F4` | `#AD1457` | `#F5F5F5` | `#EEEEEE` |
| 黑白 | 是 | `#303030` | `#E0E0E0` | `#424242` | `#424242` |
| A屏黑 | 是 | `#000000` | `#FFFFFF` | `#000000` | `#000000` |

固定语义色（`R/values/colors.xml` 与 `values-night`）：主文字 `#DE000000` / 夜 `#FFFFFFFF`；次文字 `#8A000000` / 夜 `#B3FFFFFF`；卡片底 `#F5F5F5` / 夜 `#303030`；菜单底 `#EEEEEE` / 夜 `#424242`；error `#EB4333`、success `#439B53`、highlight `#D3321B`；发现绿点 `#43A047`。

**改动**：新建 `S/Shared/Theme/ThemeStore.swift`（`@Observable`，持久化到 `AppPreferences`，与备份 `themeConfig` 字段互通）；`ThemeColors` 环境值；全局 `.tint(accent)`；导航栏与底栏底色分别取 primary / bottomBackground；`EInkModifier` 关闭动画。
**验收**：切换 4 预设与日夜，所有页面无写死颜色（grep `Color(red:` 只允许出现在 ThemeStore）。

### U1 主界面

**规格**：`R/layout/activity_main.xml`、`R/menu/main_bnv.xml`、`K/ui/main/MainActivity.kt:104-130,477-490,613-660`。
**改动**：
- `S/App/RootTabView.swift` 改为 4 tab：书架 `books.vertical` / 发现 `safari` / 订阅 `dot.radiowaves.left.and.right` / 我的 `person.crop.circle`；**只显示图标不显示文字**；底栏底色 bottomBackground，选中色 accent，未选中次文字色。
- 删除现有「搜索」占位 tab 与「书源」tab：搜索移到书架导航栏常驻按钮；书源管理移到「我的」第一项。
- `showDiscovery` / `showRss` 两个开关隐藏 tab 并重排索引。
- 再点当前 tab：书架回顶、发现收起全部分类。
- 每个 tab 各自 `NavigationStack`，导航栏标题与菜单由各页定义。

### U2 书架

**规格**：`K/ui/main/bookshelf/`（`BaseBookshelfFragment.kt:277-330`、`style1/BookshelfFragment1.kt:70-110`）、`R/layout/item_bookshelf_list.xml`、`item_bookshelf_grid.xml`、`dialog_bookshelf_config.xml`、`R/menu/main_bookshelf.xml`。

**默认形态沿用原版：分组样式「标签」+ 视图「列表」**（人类已确认）；两种分组样式与 7 档视图全部实现。

**两种分组样式**（`bookGroupStyle`，默认 0）：
- 样式 0「标签」：顶部横向可滚动的分组 tab 条（下划线指示器 accent 色、非全宽），每组一页；长按分组 tab 进入分组编辑。
- 样式 1「文件夹」：分组以文件夹格子混排在书籍网格 / 列表里，点进去展示组内书。

**视图布局**（`bookshelfLayout`，默认 0）：0 列表、1 紧凑列表、2–6 网格 2–6 列（列数就是该整数，不用自适应）。

| 列表项（HStack） | 值 |
| --- | --- |
| 封面 | 66 × 90，左侧，marginStart 8，圆角 4 |
| 书名 | 16pt 主文字，单行 |
| 作者 | 13pt 次文字，前置 18pt `person` 图标 |
| 「最近：当前章名」 | 13pt，前置 `clock.arrow.circlepath` |
| 「最新：最新章名」 | 13pt，前置 `text.badge.checkmark` |
| 上次更新时间 | 13pt，默认隐藏（`showLastUpdateTime` 默认 false） |
| 未读角标 | 红色圆角数字，封面右上；`showUnread` 默认 true |
| 加载转圈 | 26pt 叠在封面上 |
| 阅读进度条 | 封面底部 4pt，accent 色，`readProgress` 样式：隐藏 / 标准 / 增强 |

| 网格项（VStack） | 值 |
| --- | --- |
| 封面 | 宽撑满列，高 = 宽 × 4/3，圆角 12；**无卡片底色** |
| 书名 | 12pt，两行居中，可关闭 |
| 未读角标 / 22pt 转圈 / 4pt 进度条 | 叠在封面上 |

**「书架布局」弹窗**（底部 sheet）：分组样式（标签 / 文件夹）、阅读进度（隐藏 / 标准 / 增强）、显示未读标志、显示上次更新时间、显示等待更新数量、显示快速滚动条、最近阅读、数量统计、视图（7 选项）、排序（按阅读时间 / 按更新时间 / 按书名 / 手动排序 / 综合排序 / 按作者）、书架边距滑杆。

**导航栏菜单**（搜索为常驻按钮，其余进 `Menu`）：更新目录、添加本地、远程书籍、添加网址、书架管理、缓存 / 导出、分组管理、书架布局、导出书单、导入书单、日志。
**交互**：点书进阅读器；长按书直接进详情页（原版无上下文菜单）；下拉刷新 = 更新目录。

### U3 搜索页

**规格**：`R/layout/activity_book_search.xml`、`item_search.xml`、`dialog_search_scope.xml`、`R/menu/book_search.xml`、`K/ui/book/search/SearchScope.kt`。

- 导航栏内嵌胶囊搜索框（高 30、圆角 35、填充 10% 黑、0.5 描边、前置 `magnifyingglass`），常驻展开、自动聚焦。
- 搜索框下 2pt 进度条；右下角 FAB「开始 / 停止」；进度浮层「已搜 N / M」。
- **未输入时**显示输入助手层：上半「书架」标题 + 书架内匹配结果横向流式胶囊；下半「搜索历史」标题 + 右侧「清空」+ 历史词流式胶囊，长按删单条。
- 结果项：封面 80 × 110（margin 8）；书名 16 + 来源数角标；作者 12；分类标签行（胶囊 3 圆角）；最新章 12；简介 12 最多 3 行；封面角上两个 8pt 圆点：绿「已在书架」、橙「读过」。
- 多源合并按 P4-10 的 `SearchModel`，precision 四档排序。
- 菜单：精准搜索（可勾选）、标识读过的书籍、搜索结果屏蔽词、书源管理、多分组 / 书源（范围弹窗：单选「分组 / 书源」+ 多选列表 + 底部「全部书源 / 取消 / 确定」；编码 空=全部、`组A,组B`、`源名::源URL`）、日志。

### U4 发现页

**规格**：`R/layout/fragment_explore.xml`、`item_find_book.xml`、`activity_explore_show.xml`、`K/ui/main/explore/`。

- 单列表，每行一个有发现规则的书源：书源名 + 右侧 20pt 状态箭头（`chevron.right` / `chevron.down`）+ 20pt 转圈；行底色 `bg_find_book_group`（卡片色），padding 10 / 6。
- **手风琴单开**：展开新的自动收起旧的并滚动定位；展开区是流式胶囊分类（padding 3，marginTop 8）；部分书源的分类含 spinner / 输入框控件，按 `exploreUrl` 的 JSON 形态渲染。
- 长按书源：编辑 / 置顶 / 登录 / 搜索 / 刷新 / 删除。
- 导航栏常驻：分组筛选 `folder`、书源管理 `gearshape`。
- 点分类进发现书单页：顶部可滚动二级分类 tab（minHeight 40，tab paddingH 12），主体复用搜索结果项样式，上拉加载下一页。
- 空态「当前没有发现源！」。

### U5 书籍详情页

**规格**：`R/layout/activity_book_info.xml`、`R/menu/book_info.xml`。

自上而下：
1. 整页顶部模糊封面大图作背景，高约 90 + 78 的弧形过渡（弧高 78，用 `Path` 画）。
2. 封面卡片 110 × 160 浮在弧顶，圆角 8，阴影轻。
3. 书名 18pt（横向可滚动）；分类标签流。
4. 五行信息（18pt 图标 + 13pt 文字 + 右侧 13pt 动作文字）：作者；来源 + 「换源」；最新章；分组 + 「设置分组」；目录 + 「查看目录」。
5. 简介：默认折叠 4 行，底部 48pt「展开 / 收起」条（14pt）。
6. 分割线。
7. 底部固定操作条（底色菜单色，paddingH 12 / V 8）：左「放入书架 / 删除书籍」（弱强调底色），右「阅读」（accent 实心）；各高 48、15pt、圆角 8。
8. 顶部 2pt 进度条。

菜单：定制按钮 / 编辑 / 分享 常驻；溢出：上传 WebDav、刷新、生成更新任务、登录、置顶、设置源变量、设置书籍变量、拷贝书籍 URL、拷贝目录 URL、允许更新（勾选）、拆分超长章节（勾选）、删除提醒（勾选）、清理缓存、日志。
换源页：列表项 = 书源名 + 最新章 + 响应时间，顶部 2pt 进度条，支持停止与「校验」。

### U6 阅读器

**规格**：`R/layout/activity_book_read.xml`、`view_read_menu.xml`、`R/menu/book_read.xml`、`K/ui/book/read/ReadMenu.kt`、`page/ReadView.kt:741-769`、`config/ClickActionConfigDialog.kt:25-41`、`dialog_read_book_style.xml`、`dialog_read_padding.xml`、`dialog_tip_config.xml`、`R/xml/pref_config_read.xml`、`A/defaultData/readConfig.json`、`K/help/config/ReadBookConfig.kt:910-920`。
**现状**：`S/Features/Reader/ReaderView.swift` 用 7 个 `.sheet` 堆叠，底栏是 5 个文字按钮。

**6.1 页面与点击区**：全屏无导航栏；九宫格点击区可配置，14 种动作（-1 无 / 0 菜单 / 1 下一页 / 2 上一页 / 3 下一章 / 4 上一章 / 5 朗读上一段 / 6 朗读下一段 / 7 添加书签 / 8 编辑内容 / 9 替换开关 / 10 目录 / 11 全文搜索 / 12 同步进度 / 13 朗读暂停继续）；默认中中 = 菜单，下中 = 下一页，上左 / 上中 = 上一页；至少一区必须是菜单。

**6.2 覆盖式菜单 ReadMenu**（不是 sheet，是叠在正文上的透明层，顶栏与底栏同时淡入，E-Ink 无动画）：
- 顶栏：返回、书名（标题）、章节名 + 章节 URL（副行）、「书源」胶囊按钮（点开换源）、定制按钮、更多。更多菜单：换源 / 刷新 / 离线缓存 常驻；溢出：添加书签、高亮规则、编辑内容、翻页动画（本书）、拉取云端进度、覆盖云端进度、反转内容、模拟追读、替换管理、手动替换、移除重复标题、重新分段、段评、删除 ruby 标签、删除 h 标签、图片样式、重新导入本书书源、TXT 目录规则、设置编码。
- 左侧竖直亮度条：圆角 5 半透明容器，顶 24pt 自动亮度图标，底 24pt 换边图标；`showBrightnessView` 可隐藏。
- 右侧一列浮动小圆按钮：全文搜索 `magnifyingglass`、自动翻页 `play.rectangle`、替换管理 `arrow.2.squarepath`、深色模式 `moon`。
- 底栏第一行：「上一章」(14pt) — 章节进度 Slider（高 25）— 「下一章」(14pt)。
- 底栏第二行四个图标 + 12pt 文字：目录 `list.bullet` / 朗读 `speaker.wave.2` / 界面 `textformat.size` / 设置 `gearshape`。

**6.3 「界面」面板**（底部 sheet，不遮正文）：
- 顶部横滚胶囊按钮行（14pt，圆角 3）：字重转换器、字体、缩进、繁简转换、边距、信息。
- 四条带标题与数值的滑杆（marginH 16）：字号 5–50（默认 20）、字间距 0–100 映射 -0.5–0.5（默认 0.1）、行距 0–50（默认 12）、段距 0–20 显示 /10（默认 2）。
- 翻页动画单选一行：覆盖 / 滑动 / 仿真 / 滚动 / 无动画（默认覆盖；E-Ink 默认无）。
- 「文字颜色和背景（长按自定义）」+「共用布局」勾选 + 横向 48pt 圆形色块列表（左右 margin 6），6 套预设，长按进背景 / 文字自定义面板（样式名、文字色 / 背景色 / 强调色取色、背景图片、透明度、导入 / 导出 / 删除）。

| # | 名称 | 日间底 / 字 | 夜间底 / 字 |
| --- | --- | --- | --- |
| 0 | 微信读书（默认） | `#C0EDC6` / `#0B0B0B` | `#000000` / `#ADADAD` |
| 1 | 预设1 | `#FFFFFF` / `#000000` | `#000000` / `#FFFFFF` |
| 2 | 预设2 | `#DDC090` / `#3E3422` | `#3C3F43` / `#DCDFE1` |
| 3 | 预设3 | `#C2D8AA` / `#596C44` | `#3C3F43` / `#88C16F` |
| 4 | 预设4 | `#DBB8E2` / `#68516C` | `#3C3F43` / `#F6AEAE` |
| 5 | 预设5 | `#ABCEE0` / `#3D4C54` | `#3C3F43` / `#90BFF5` |

预设 0 的排版：textSize 24、行距 10、段距 6、字间距 0、段首两个全角空格、页边距 左右 22 / 上 5 / 下 4、页眉 padding 19 / 10 / 16 / 0、页脚 13 / 0 / 17 / 10、页眉页脚显示分隔线。

**6.4 边距面板**：页眉 / 正文 / 页脚三组，各 上（0–400）/ 下（0–400）/ 左（0–100）/ 右（0–100），「左右边距联动」「显示分隔线」。

**6.5 信息面板**：页眉与页脚各 左 / 中 / 右 三个槽，每槽 12 选 1：无 / 书名 / 标题 / 时间 / 电量 / 电量% / 页数 / 进度(%) / 进度(xx/yyy) / 页数及进度 / 时间及电量 / 时间及电量%；默认页眉 左=书名 右=标题，页脚 左=进度(%) 右=页数。另有标题位置（左 / 中 / 右 / 隐藏）、标题字号 / 行距 / 字体 / 字重 / 颜色、章节序号样式、上下间距。

**6.6 「设置」面板**：`R/xml/pref_config_read.xml` 的 40 项**全部实现**，Android 专有项按 iOS 能力映射，不做删减：

| Android 项 | iOS 实现 |
| --- | --- |
| 隐藏状态栏 | `statusBarHidden` |
| 隐藏导航栏 | 隐藏 Home 指示条（`persistentSystemOverlays(.hidden)`） |
| 扩展到刘海 / 填充刘海区域 | `ignoresSafeArea` 两档 |
| 屏幕方向 / 屏幕超时 | `supportedInterfaceOrientations` / `isIdleTimerDisabled` |
| 鼠标滚轮翻页 / 速度 | iPad 触控板与外接鼠标滚轮事件 |
| 音量键翻页（含播放时） | iOS 不允许拦截音量键：面板保留该项但置灰并注明「iOS 不支持」，记入 `settings-compat.md` |
| 按键长按翻页 / 自定义翻页按键 | 外接键盘按键（`onKeyPress`） |
| 禁用返回键 | 禁用侧滑返回手势 |
| 其余 31 项（双页、进度条行为、中文分行、两端对齐、悬挂标点、标点挤压、底部对齐、特殊样式、下拉书签及距离、翻页触发距离、点击判定、自动换源、长按选择文本 / 整段、双指替换预览、显示亮度条、无动画滚动翻页、点击图片方式、高亮触发方式、渲染优化、点击区域设置、自定义选择菜单、自定义阅读菜单、标题附加信息等） | 直接实现，默认值取 `AppConfig` |

**6.7 目录页**：独立全屏页（不是抽屉）；导航栏内居中 tab「目录 / 书签」（EPUB 多级目录可折叠，PDF 另有「大纲」tab）；进入自动定位当前章、当前章 accent 高亮；菜单：搜索常驻、TXT 目录规则、拆分超长章节、反转目录、目录展开、使用替换、加载字数、导出书签、导出 md、日志；章节行显示缓存状态（已缓存的字色更深）。

**6.8 翻页动画**：覆盖 / 滑动 / 仿真 / 滚动 / 无，现有 `S/Features/Reader/PageAnimation/` 五个实现保留，对齐默认值与 E-Ink 强制项。

### U7 书源管理与编辑

**规格**：`R/layout/item_book_source.xml`、`activity_book_source.xml`、`activity_book_source_edit.xml`、`item_source_edit.xml`、`activity_source_debug.xml`、`R/menu/book_source.xml`、`K/ui/book/source/edit/BookSourceEditActivity.kt:313-331,484-600`、`A/defaultData/keyboardAssists.json`。

- **列表项**（padding 16）：多选态左侧勾选框；书源名 16pt + JS 角标 10pt；书架使用数 12pt 次文字；启用 `Toggle`；编辑 36pt `pencil`；更多 36pt `ellipsis`，其右上角 8pt 绿点 `#43A047` 表示「发现可用」（不是第二个开关）；无拖拽手柄，手动排序模式下长按整行拖拽。
- 导航栏内嵌胶囊搜索框；分组筛选往搜索框写 `group:<名>`；搜索框下 48pt 校验状态筛选条（可隐藏）；多选时底部操作条（全选 / 反选 / 主操作 / 更多）。
- 菜单：排序（反序 + 手动 / 智能 / 名称 / 地址 / 更新时间 / 响应时间 / 是否启用）、分组（分组管理 / 已启用 / 已禁用 / 需要登录 / 未分组 / 已启用发现 / 已禁用发现 + 动态分组）、新建书源、新建 JS 书源、本地导入、网络导入、二维码导入、按域名分组显示、显示检验状态、禁止网页跳转、帮助。
- **编辑页**：顶部可折叠「设置」卡片（圆角 8、卡片色、行高 48：书籍类型、启用、发现、自动保存 Cookie、段评、事件监听、自定义按钮）；7 个分区 tab（高 36）：基本 / 搜索 / 发现 / 详情 / 目录 / 正文 / 段评；第二行可滚动字段导航 tab（高 48）；字段列表每项 = 标签 + 多行代码输入框（minHeight 48、paddingH 12、等宽字体）。字段清单按 Kotlin 顺序：
  - 基本：源URL、源名称、源分组、源注释、登录URL、登录UI、登录检查JS、封面解密、书籍URL正则、请求头、变量说明、并发率、jsLib
  - 搜索：搜索地址、校验关键字、书籍列表、书名、作者、分类、字数、最新章节、简介、封面、详情页URL
  - 发现：发现地址 + 同搜索后 9 项
  - 详情：预处理、书名、作者、分类、字数、最新章节、简介、封面、目录URL、允许改名、下载URL
  - 目录：更新前JS、目录列表、章节名称、章节URL、格式化、Volume标识、章节信息、VIP标识、购买标识、下一页
  - 正文：正文、下一页URL、副文、替换、章节名称、资源正则、图片样式、图片解密、WebViewJS、购买操作、回调、批量正文、最大批量
  - 段评：20 项（统计 / 详情 / 回复三组）
  - 键盘辅助栏：贴键盘上沿的横向按键网格，32 个默认键来自 `keyboardAssists.json`，1–5 行可配。
- **调试页**：导航栏搜索框 + 日志流列表 + 居中转圈；聚焦时显示 5 条中文用法示例（书名 / 书籍URL / 目录URL / 正文URL / 发现）。
- 导入预览页：列表 + 「新增 / 更新 / 相同」标记 + 全选 + 分组记忆。

### U8 我的 / 设置

**规格**：`R/xml/pref_main.xml`、`pref_config_theme.xml`、`pref_config_other.xml`、`pref_config_backup.xml`、`R/menu/main_my.xml`。

「我的」是一个 `List`，每项 24pt 单色图标 + 标题 + 副标题：
- 无分组：书源管理 `tray.full`、定时任务、运行定时任务（开关）、TXT 目录规则、替换管理 `arrow.2.squarepath`、字典规则、主题模式（列表页上直接四选一）、Web 服务（开关）、MCP 服务（开关，本轮只留项不实现）。
- 「设置」组：备份与恢复 `externaldrive`、主题设置 `paintpalette`、其它设置 `slider.horizontal.3`。
- 「其他」组：书签、阅读记录 `clock.arrow.circlepath`、文件管理、关于 `info.circle`、退出。
- 导航栏菜单：帮助。

主题设置：切换图标（6 套备用图标已在 `App/Resources/AlternateIcons/`）、启动界面样式、字体大小、封面设置、主题列表、跟随壁纸配色；「白天」「夜间」两组各：主色调 / 强调色 / 背景色 / 底部操作栏颜色 / 背景图片 / 保存主题配置。
其它设置：语言；「主界面」组 = 自动刷新 / 仅更新已读完 / 自动跳转最近阅读 / 显示发现 / 显示订阅 / 默认主页；「其它设置」组 = 用户代理、自定义 Hosts、书籍保存位置、源编辑框最大行数、校验设置、直链上传规则、图片绘制缓存、漫画保留数量、预下载、清理缓存、压缩数据库、线程数、记录日志。
备份与恢复：「WebDav 设置」组（服务器地址 / 账号 / 密码 / 子文件夹 / 设备名称 / 恢复缺失本地书 / 同步阅读进度 / 同步增强）+「备份与恢复」组（本地密码 / 备份路径 / 备份内容 / 备份 / 恢复 / 恢复忽略列表 / 仅保留最新备份 / 自动备份 / 自动检查新备份）。现有 `S/Features/Settings/` 下的页面按此重排，删除原版没有的分组名。

### U9 通用组件与图标

新建 `S/Shared/Components/`：
- `LegadoTitleBar`：标题 + 副标题 + 常驻按钮 + 溢出 `Menu`；E-Ink 用描边替代阴影。
- `RefreshProgressBar`：2pt。
- `CapsuleSearchField`：高 30、圆角 35、10% 填充、0.5 描边。
- `DetailSeekBar`：标题 + 数值 + Slider。
- `LabelsBar`：流式胶囊标签（圆角 3）。
- `CoverImage`：强制 3:4，圆角参数化，占位用书名首字。
- `BadgeView`：未读角标。
- `SelectActionBar`：多选底栏。
- `LoadingView` / `EmptyText`。
- `ReadStyleCircle`：48pt 配色圆块。

图标映射（Legado → SF Symbols）：`ic_bottom_books` books.vertical；`ic_bottom_explore` safari；`ic_bottom_rss_feed` dot.radiowaves.left.and.right；`ic_bottom_person` person.crop.circle；`ic_search` magnifyingglass；`ic_more_vert` ellipsis；`ic_toc` list.bullet；`ic_read_aloud` speaker.wave.2；`ic_interface_setting` textformat.size；`ic_settings` gearshape；`ic_brightness` moon；`ic_brightness_auto` sun.max；`ic_auto_page` play.rectangle；`ic_auto_page_stop` stop.circle；`ic_find_replace` arrow.2.squarepath；`ic_bookmark` bookmark；`ic_bookmark_filled` bookmark.fill；`ic_edit` pencil；`ic_add` plus；`ic_import` square.and.arrow.down；`ic_export` square.and.arrow.up；`ic_scan` qrcode.viewfinder；`ic_share` square.and.arrow.up；`ic_refresh_black_24dp` arrow.clockwise；`ic_exchange` arrow.left.arrow.right；`ic_groups` folder；`ic_sort` arrow.up.arrow.down；`ic_author` person；`ic_history` clock.arrow.circlepath；`ic_check_source` checkmark.seal；`ic_backup` externaldrive；`ic_web_outline` globe；`ic_screen` rotate.right；`ic_cfg_source` tray.full；`ic_cfg_replace` arrow.2.squarepath；`ic_cfg_theme` paintpalette；`ic_cfg_backup` externaldrive；`ic_cfg_other` slider.horizontal.3；`ic_cfg_about` info.circle。

**UI 验收方式**：非 UI 逻辑（布局枚举、排序、范围编码、点击区映射、色值表）进 `tools/appcore-check` 单测；每屏做一张 iPhone 模拟器截图与 Android 同屏截图并排放进 `docs/5-UI对齐与解析补全/assets/`，由人类在 `/finish` 时目视验收。

## 5. 真实回归与真机验证

1. **书源回归集（两层都做）**：① 精选集：Codex 自行从用户备份里挑 20 个（覆盖 `@js:`、JSONPath、XPath、`loginCheckJs`、多页目录、多页正文、图片正文、纯 JS 书源各 ≥ 2 个），用 `tools/conformance-run` 与真实网络跑搜索 / 详情 / 目录 / 正文四流程，目标 ≥ 16 / 20 通过；② 全量冒烟：用户备份里的**全部书源**各跑一次搜索（关键字取书源自带 `checkKeyWord`，没有则用「我的」），只记通过 / 失败 / 超时三态，出一张表进 SUMMARY。不通过的逐条归因（书源失效 / 引擎缺陷 / 网络），引擎缺陷回流成新单元。
2. **本地书回归集**：§P7 fixture 全部导入并翻到最后一章。
3. **真机（两次）**：批次 3 结束做中期真机（阅读器覆盖式菜单、本地书全格式、整架更新），批次 5 做最终真机；每次都恢复用户的坚果云备份后整架更新，对比 14 / 47 的基线，内存峰值 ≤ 300 MB；两次结果都写成 `DEVICE-READING-<日期>.md`。
4. **备份互导**：iOS 导出的备份包在 Android 端恢复不报错（尤其 TXT 章节 url 与 EPUB 封面路径对齐后）。

## 6. 关键设计决策

| 决策 | 结论 | 理由 |
| --- | --- | --- |
| UI 技术 | 继续 SwiftUI，不引入 UIKit 重写；阅读器正文层保留现有 `Paginator` + 翻页动画实现 | 已有 1.1 万行可复用；对齐的是视觉参数不是渲染栈 |
| 主题 | 运行时 `ThemeStore` 四色槽 × 日夜，与备份 `themeConfig` 互通 | 原版就是运行时主题，写死任何一套都不「像原版」 |
| XPath | 在 SwiftSoup DOM 上自研求值器，libxml2 桥接降为 fallback | 三条硬差异源于重解析，单点修补无效（`xpath-compat.md`） |
| 简繁转换 | **已同意**：内置 OpenCC（Apache-2.0）的 `STCharacters` / `TSCharacters` 单字表 + `STPhrases` / `TSPhrases` 词表（从 OpenCC 仓库取原文件，记录 tag 与 commit，LICENSE 随文件进 `Resources/`），不引第三方库 | Android 用 HanLP 词表，逐字对拍时以取回的表为准 |
| rar / 7z | **必做，不接受降级为只做 zip**。引入 SwiftPM 可用的实现（候选顺序：`PLzmaSDK`（7z + rar 解压）→ `Unrar` + `SWCompression`），选型前先在 `tools/` 起最小验证包实测能解出 fixture；一个候选失败就换下一个，全部失败才停机向人类报告并附各候选的失败原文 | wrapper 原则：先核实原生能力再封装；人类已明确要求全做 |
| PDF | 渲染页图（对齐 Android），文本抽取不再作正文 | 扫描版 PDF 是常见输入 |
| 代理 / DNS | `connectionProxyDictionary` + 「IP 直连 + Host 头」 | URLSession 无自定义 DNS 钩子 |
| toast 通道 | Core 定义 `HostUI` 协议，App 注入 overlay 实现 | Core 不依赖 SwiftUI |
| 正文缓存路径 | 沿用已对齐的 `book_cache/<name9+md5_16>/%05d-<md5_16>.nb` | 备份互导依赖 |
| 不做项 | `@webjs:`、E4X、`%%` 打磨、书源类型 3 / 4、Android 独有系统项 | 语料使用率 0% 或 iOS 无对应能力 |

## 7. 批次与顺序

| 批次 | 单元 | 依赖 | 说明 |
| --- | --- | --- | --- |
| 0 | P0 | — | 先把工作树落地，1 天内 |
| 1 | P1、P2、P3a–3d、U0、U9 | — | 解析线修 P0 与最高频宿主方法；UI 线先立主题与组件库。四者文件不重叠可并行 |
| 2 | P4、P5、P6、U1、U2、U3 | P1–P3、U0、U9 | 四流程接线与主界面 / 书架 / 搜索 |
| 3 | P7、P8、P3e–3f、U4、U5、U6 | P4（缓存）、U9 | 本地书整类补齐 + 阅读器覆盖式菜单 |
| 4 | P9、P3g–3h、U7、U8 | P3b（ByteArray 桥） | XPath 自研求值器是本批最大单元，单独派 |
| 5 | §5 回归与真机 | 全部 | 出 SUMMARY |

每批内单元并行（文件不重叠），批内全部过 `/review-loop` 后合并跑一次全量单测 + `xcodebuild build` + `tools/build-ipa.sh`，再进入下一批。每个单元完成即 commit，不攒。

## 8. 人类已确认的决策（2026-09-18）

人类原话：「我希望都做，就是这样我能让他一直做。」六项全部按最大范围定案，Codex 不必再问：

| # | 事项 | 定案 |
| --- | --- | --- |
| 1 | 书架默认形态 | 沿用原版默认「标签 + 列表」；两种分组样式、7 档视图布局全部实现（§U2） |
| 2 | 阅读器「设置」面板 | 40 项全做，Android 专有项按 §U6.6 的映射表实现；只有「音量键翻页」因 iOS 不允许拦截音量键而置灰注明 |
| 3 | rar / 7z | 必做，不接受只做 zip；候选库依次实测，全部失败才停机报告（§6） |
| 4 | 真实书源回归集 | 两层都做：Codex 自选 20 个精选集跑四流程 + 用户备份里全部书源跑搜索冒烟（§5） |
| 5 | 真机验证 | 两次：批次 3 结束一次、批次 5 一次（§5） |
| 6 | 简繁转换词表 | 同意引入 OpenCC 词表（§6） |

**执行纪律由此推出**：批次做完直接进下一批，不停下等指令；遇到本文未覆盖的取舍，按「范围更大、更接近 Android 原版」的一边选并在 `PROGRESS.md` 留一行，只有 §6 定义的停机条件（候选全失败、关键技术假设证伪）才停。

## 9. 给 Codex 的执行说明

- **仓库与分支**：`/Users/xiling/Work/legado-ios` 主 checkout 是 `master`（Kotlin 规格，只读）；iOS 代码在 worktree `.claude/worktrees/ios`（分支 `ios`），**所有改动只在这个 worktree 里做**。本文所有 K/ R/ A/ 路径指向 master 树，C/ S/ 指向 ios worktree。
- **工作模式**：遵守 worktree 根 `CLAUDE.md`（任务书六要素、核验义务、`PROGRESS.md` 断点续传、子 agent 通道限定 Opus@high 或 Codex astra@medium）与全局 Development Constitution（TDD、每次 commit 前 `/review-loop`、commit message 中文、`Co-authored-by: OpenAI Codex <noreply@openai.com>`）。
- **进度文件**：`docs/5-UI对齐与解析补全/PROGRESS.md`，每派出 / 收回一个单元、每次 commit 后更新，≤ 80 行。
- **环境命令**（都在 ios worktree 根目录；详见 `docs/HANDOFF.md` §3）：

  ```bash
  # LegadoCore 单测
  CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/clang-cache" TMPDIR="$PWD/.build/tmp" \
    swift test --package-path Packages/LegadoCore --cache-path "$PWD/.build/cache" --disable-sandbox --disable-automatic-resolution --skip-update
  # App 非 UI 逻辑单测（新增 App 逻辑文件要在 tools/appcore-check/Package.swift 追加软链目标）
  ... --package-path tools/appcore-check ...
  # iOS 构建（Codex 沙箱写不了 ~/Library，只有主会话能跑）
  CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache" xcodebuild -project App/Legado.xcodeproj -scheme Legado \
    -destination 'generic/platform=iOS' -configuration Debug -derivedDataPath .build/DerivedData \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
  bash tools/build-ipa.sh
  ```

- **工程文件**：`App/project.yml` 是真源，改后 `cd App && xcodegen generate`，生成物一起提交。
- **新依赖**：只有 §6 列出的（压缩库、OpenCC 词表）允许引入；引入前先在 `tools/` 起最小验证包实测。Codex 沙箱无网络，`swift package resolve` 由主会话跑。
- **禁止**：push、开 PR、开 issue 等一切对外动作；修改 master 树；把 `.env.local` 里的 WebDAV 凭据用于任何写操作（授权只读）。
- **每个单元的交付**：改动文件清单、测试原始输出尾部、未解决项、`file:line` 证据；解析单元附与 Kotlin 对拍的输入输出表；UI 单元附截图路径。
