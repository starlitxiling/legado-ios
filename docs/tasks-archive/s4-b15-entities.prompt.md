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
目标：阶段 4 单元 B15 —— 实体与表补齐：盘点 Android data/entities 全部实体与 AppDatabase 表，与 LegadoCore/Entities + Storage 逐一对照，补齐尚缺的实体、表、Repository 与备份导入 / 导出（SearchKeyword、HighlightRule 若存在、ReadRecordDetail、Server、KeyboardAssist、RuleSub、BookGroup 缺字段、Cache 表等），并把 BackupImporter / BackupExporter 的文件清单补到与 Restore.kt / Backup.kt 完全一致。
工作目录：/Users/wujie/Work/legado-ios/.claude/worktrees/ios。工程：App/（XcodeGen 按目录收集，**不要运行 xcodegen、不改 project.yml / .xcodeproj**；新文件放 App/Sources/Features/<功能>/ 或 App/Sources/Shared/）；LegadoCore 在 Packages/LegadoCore（可新增目录与 public 入口，尽量不改既有文件；改动逐处列出）。已有能力：AnalyzeRule 引擎、AnalyzeUrlExecutor（含 webView 分支）、JsEngine/JavaHost、WebBook、Storage（Repository、AppDatabase.write、Migrations v1–v3、SourceStateRepository）、Entities、Network、Login/（SourceScriptBridge）、CheckSource/、LocalBook/（TXT / EPUB / MOBI / PDF）、Explore/、Images/、Backup/、WebView/、JsSource/、TTS/、Content/ContentProcessor、Reader/、Debug/、Export/、Cache/（CacheBook、BookExporter、BookHelp）；App 端 Features/{Bookshelf,Sources,ReplaceRules,Search,BookDetail,Toc,Reader,Settings,Backup,Explore,SourceLogin,CheckSource,LocalImport,Browser,ReadAloud,Download}、Shared/{Theme,EmptyStateView,KeychainStore,RemoteImage,HeadlessWebView}。ViewModel 与纯逻辑放不 import UIKit / SwiftUI 的文件，用 @Observable；单测走 tools/appcore-check（追加自己的目标，软链引用 App 下非 UI 文件）与 LegadoCore 测试。你不能跑 xcodebuild（主会话代跑）。并行任务会改其他目录与 RootTabView / AppContainer / JavaHost / Reader / Settings / BackupImporter 的不同区域：改共享文件前重新读取、只做最小局部插入、不重写。**验证一律在工作区内，不在 /tmp 做隔离副本**；swift test 用 CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/clang-cache" TMPDIR="$PWD/.build/tmp"（先 mkdir -p .build/tmp）--cache-path "$PWD/.build/cache" --disable-sandbox --disable-automatic-resolution --skip-update；磁盘只有约 3 GB，节省，不留大日志。Kotlin 只读，commit cb664b84d，路径前缀 /Users/wujie/Work/legado-ios/app/src/main/java/io/legado/app/。Swift 语言模式 5；不加第三方依赖；不 commit；不联网。TDD 先红后绿；报告附命令与末尾 10 行、测试总数。汇报格式：中文 markdown ≤ 60 行。
Kotlin 规格：data/entities/*.kt 全部（先 ls 列清单）、data/AppDatabase.kt 的 entities 数组与版本、data/dao/*、help/storage/{Backup,Restore}.kt 的文件清单、ui/rss/subscription（RuleSub）、ui/book/searchContent / SearchKeyword 用途、data/entities/Server.kt（WebDAV 多服务器配置）、KeyboardAssist（阅读器辅助键）。
产出：
1. 先输出对照表（Kotlin 实体 / Swift 已有 / 缺失 / 本单元补齐），写进 docs/spec/entities-compat.md（只记实体名、字段差异与理由；不贴数据）。
2. LegadoCore：缺失实体 Codable + 表 + 迁移 v7 + Repository；BackupImporter / BackupExporter 补文件；SourceImporter 补 RuleSub（订阅规则）导入与「从 URL 订阅」的解析（网络经 HttpClient 注入）。
3. App：Features/Settings 下补 RuleSub 订阅管理页与 Server（WebDAV 多服务器）管理页；SearchKeyword 接入搜索页历史（最小插入）。
4. 测试：每个新实体 JSON round-trip（与 Android 字段名一致）、迁移 v7 在 v6 库上可升级且旧数据保留、备份导入文件清单覆盖测试（合成 zip 含全部文件）、RuleSub 解析。并行的 B11–B14 会新增自己的表与迁移版本号（v6 由 B11 占用）：改 Migrations 前重新读取，用独立的迁移名，不重编号别人的。
</task>
