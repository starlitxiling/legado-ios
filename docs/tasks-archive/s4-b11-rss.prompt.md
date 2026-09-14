<subagent_contract>
你是一个子代理。你的最后一条消息是唯一交付物，调用方看不到其他任何内容。必须遵守：
1. 所有发现、结论、文件路径都写进最后一条消息；禁止以计划、提问或"接下来我会…"收尾——先做完，再汇报。
2. 第一段先给结论（发生了什么/发现了什么），细节放后面。
3. 涉及代码的每条论断都带 `文件绝对路径:行号` 引用。
4. 如实汇报：测试失败就原样贴失败输出；跳过的步骤要说明；没验证过的事不得声称完成；不确定就标注"未验证"。
5. 只做指派的任务：不扩 scope、不顺手重构、不 commit/push（除非任务书明确要求）。
6. 改代码时贴合周边代码风格；注释只写代码本身无法表达的约束，不写解释本次改动的注释。
7. 用完整句子；禁止碎片化短语、箭头链（A→B）、自造缩写和代号、表情符号。
8. 被卡住就停下，精确说明缺什么信息；不许猜测、不许编造。
</subagent_contract>

<task>
目标：阶段 4 单元 B11 —— RSS：订阅源（RssSource）导入 / 管理 / 分组，文章列表（ruleArticles / ruleNextPage / 分页去重）、文章正文（ruleContent、内容为 URL 时直接加载、样式注入 style）、WKWebView 阅读页（含 loadWithBaseUrl、白名单 / 拦截、JS 注入）、收藏（RssStar）与已读状态、备份导入 rssSources.json / rssStar.json 接入 BackupImporter。
工作目录：/Users/wujie/Work/legado-ios/.claude/worktrees/ios。工程：App/（XcodeGen 按目录收集，**不要运行 xcodegen、不改 project.yml / .xcodeproj**；新文件放 App/Sources/Features/<功能>/ 或 App/Sources/Shared/）；LegadoCore 在 Packages/LegadoCore（可新增目录与 public 入口，尽量不改既有文件；改动逐处列出）。已有能力：AnalyzeRule 引擎、AnalyzeUrlExecutor（含 webView 分支）、JsEngine/JavaHost、WebBook、Storage（Repository、AppDatabase.write、Migrations v1–v3、SourceStateRepository）、Entities、Network、Login/（SourceScriptBridge）、CheckSource/、LocalBook/（TXT / EPUB / MOBI / PDF）、Explore/、Images/、Backup/、WebView/、JsSource/、TTS/、Content/ContentProcessor、Reader/、Debug/、Export/、Cache/（CacheBook、BookExporter、BookHelp）；App 端 Features/{Bookshelf,Sources,ReplaceRules,Search,BookDetail,Toc,Reader,Settings,Backup,Explore,SourceLogin,CheckSource,LocalImport,Browser,ReadAloud,Download}、Shared/{Theme,EmptyStateView,KeychainStore,RemoteImage,HeadlessWebView}。ViewModel 与纯逻辑放不 import UIKit / SwiftUI 的文件，用 @Observable；单测走 tools/appcore-check（追加自己的目标，软链引用 App 下非 UI 文件）与 LegadoCore 测试。你不能跑 xcodebuild（主会话代跑）。并行任务会改其他目录与 RootTabView / AppContainer / JavaHost / Reader / Settings / BackupImporter 的不同区域：改共享文件前重新读取、只做最小局部插入、不重写。**验证一律在工作区内，不在 /tmp 做隔离副本**；swift test 用 CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/clang-cache" TMPDIR="$PWD/.build/tmp"（先 mkdir -p .build/tmp）--cache-path "$PWD/.build/cache" --disable-sandbox --disable-automatic-resolution --skip-update；磁盘只有约 3 GB，节省，不留大日志。Kotlin 只读，commit cb664b84d，路径前缀 /Users/wujie/Work/legado-ios/app/src/main/java/io/legado/app/。Swift 语言模式 5；不加第三方依赖；不 commit；不联网。TDD 先红后绿；报告附命令与末尾 10 行、测试总数。汇报格式：中文 markdown ≤ 60 行。
Kotlin 规格：data/entities/{RssSource,RssArticle,RssStar,RssReadRecord}.kt（字段全集与默认值、sortUrl 多栏目语法「名称::url」换行分隔、articleStyle、loadWithBaseUrl、enableJs、singleUrl、injectJs、contentWhitelist、shouldOverrideUrlLoading）、model/rss/{Rss,RssParserByRule,RssParserDefault}.kt（规则解析 vs 默认 XML RSS/Atom 解析的分派条件、字段：title / pubDate / description / image / link / content、link 相对路径补全、分页 nextPageUrl、去重键）、ui/rss/source/{RssSourceViewModel,edit/RssSourceEditViewModel}.kt、ui/rss/article/RssArticlesViewModel.kt、ui/rss/read/ReadRssViewModel.kt（正文获取、收藏、分享、图片长按保存不做）、ui/rss/favorites/、help/storage/Restore.kt 中 rss 相关顺序。
产出：
1. LegadoCore：Rss/{RssSource 实体（Entities/）,RssParser.swift（规则版复用 AnalyzeRule，默认版用 Foundation XMLParser 解析 RSS 2.0 与 Atom）,RssService.swift（源 → 文章列表分页 / 正文）}、Storage 表 rssSources / rssArticles / rssStars / rssReadRecords + 迁移 v6 + Repository、BackupImporter 接入（回源 Restore.kt 顺序，改动逐处列出）、SourceImporter 补 RSS 源 JSON 导入（含数组 / 单对象 / url 数组形态）。
2. App：Features/Rss/{RssSourceListView,RssSourceEditView,RssArticlesView（栏目 tab + 分页加载）,RssReadView（WKWebView 复用 Shared/HeadlessWebView 的配置思路但可见；injectJs、style、白名单）,RssFavoritesView}；RootTabView 加 RSS tab（最小插入）。
3. 测试：默认 XML 解析（RSS 2.0 与 Atom 各一份合成 fixture）、规则解析（合成 HTML fixture + ReplayHttpClient，含 nextPage 分页与去重）、sortUrl 多栏目解析、相对链接补全、收藏 round-trip、备份导入落库、源 JSON 导入三种形态。
</task>
