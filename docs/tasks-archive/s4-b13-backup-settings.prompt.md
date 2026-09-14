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
目标：阶段 4 单元 B13 —— 备份上传与设置对齐：备份打包（与 Android Backup.kt 同名同结构的 zip：bookSource.json、bookshelf.json、replaceRule.json、readRecord.json、bookmark.json、rssSources.json、rssStar.json、txtTocRule.json、dictRule.json、httpTTS.json、config 偏好 JSON 等，缺的实体写空数组）、WebDAV 上传（PUT 到 legado/backup<时间>.zip、保留数量清理、上传前 MKCOL；**测试只用假客户端，禁止对真实服务器 PUT / MKCOL / DELETE / MOVE**）、本地备份导出（Files 分享）、自动备份触发条件、设置项对齐（主题 / 语言 / 其他设置：ui/config 下 ThemeConfig、OtherConfig、BackupConfig 的各项）。
工作目录：/Users/wujie/Work/legado-ios/.claude/worktrees/ios。工程：App/（XcodeGen 按目录收集，**不要运行 xcodegen、不改 project.yml / .xcodeproj**；新文件放 App/Sources/Features/<功能>/ 或 App/Sources/Shared/）；LegadoCore 在 Packages/LegadoCore（可新增目录与 public 入口，尽量不改既有文件；改动逐处列出）。已有能力：AnalyzeRule 引擎、AnalyzeUrlExecutor（含 webView 分支）、JsEngine/JavaHost、WebBook、Storage（Repository、AppDatabase.write、Migrations v1–v3、SourceStateRepository）、Entities、Network、Login/（SourceScriptBridge）、CheckSource/、LocalBook/（TXT / EPUB / MOBI / PDF）、Explore/、Images/、Backup/、WebView/、JsSource/、TTS/、Content/ContentProcessor、Reader/、Debug/、Export/、Cache/（CacheBook、BookExporter、BookHelp）；App 端 Features/{Bookshelf,Sources,ReplaceRules,Search,BookDetail,Toc,Reader,Settings,Backup,Explore,SourceLogin,CheckSource,LocalImport,Browser,ReadAloud,Download}、Shared/{Theme,EmptyStateView,KeychainStore,RemoteImage,HeadlessWebView}。ViewModel 与纯逻辑放不 import UIKit / SwiftUI 的文件，用 @Observable；单测走 tools/appcore-check（追加自己的目标，软链引用 App 下非 UI 文件）与 LegadoCore 测试。你不能跑 xcodebuild（主会话代跑）。并行任务会改其他目录与 RootTabView / AppContainer / JavaHost / Reader / Settings / BackupImporter 的不同区域：改共享文件前重新读取、只做最小局部插入、不重写。**验证一律在工作区内，不在 /tmp 做隔离副本**；swift test 用 CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/clang-cache" TMPDIR="$PWD/.build/tmp"（先 mkdir -p .build/tmp）--cache-path "$PWD/.build/cache" --disable-sandbox --disable-automatic-resolution --skip-update；磁盘只有约 3 GB，节省，不留大日志。Kotlin 只读，commit 2bdd3c58b，路径前缀 /Users/wujie/Work/legado-ios/app/src/main/java/io/legado/app/。Swift 语言模式 5；不加第三方依赖；不 commit；不联网。TDD 先红后绿；报告附命令与末尾 10 行、测试总数。汇报格式：中文 markdown ≤ 60 行。
Kotlin 规格：help/storage/{Backup,Restore,BackupConfig}.kt（文件清单与顺序、preference 导出哪些 key、备份文件名格式 backup<yyyy-MM-dd HH-mm-ss>.zip 回源确切格式、自动备份间隔）、help/AppWebDav.kt（backUpDir、MKCOL 时机、上传、旧备份清理策略保留数、同步阅读进度 bookProgress 上传与下载的 JSON 结构与文件名）、lib/webdav/WebDav.kt（PUT 头、覆盖语义）、ui/config/{ThemeConfigFragment,OtherConfigFragment,BackupConfigFragment}.kt 与 help/config/AppConfig.kt（设置项全集与默认值）。已有：Backup/BackupArchive（zip 读）、BackupImporter、WebDavBackupSource、WebDAV/WebDavClient（PROPFIND / GET 已实现，写方法若已有则接入）。
产出：
1. LegadoCore：Backup/{BackupExporter.swift（从 Repository 拉数据写 zip，store 模式，可注入 clock）,WebDavBackupUploader.swift（经 HttpClient 注入，MKCOL + PUT + 清理旧备份）,BookProgressSync.swift（阅读进度上传 / 下载合并：以更新时间新者为准）}、WebDavClient 补 PUT / MKCOL / DELETE（协议层，只在测试用假客户端调用）。
2. App：Features/Backup 补「备份到 WebDAV / 本地导出 / 恢复 / 自动备份开关 / 进度同步开关」、Features/Settings 补主题（浅 / 深 / 跟随系统、E-ink）、语言、其他设置（预下载章节数、线程数、缓存清理、默认书架排序等）各项，对齐 AppConfig 的 key 名以便备份 JSON 互通。
3. 测试：备份 zip 结构与 JSON 内容 round-trip（导出后用 BackupImporter 导回一致）、文件名格式、假 WebDAV 客户端断言 MKCOL / PUT 的 URL 与 body、旧备份清理保留 N 份、进度合并规则、偏好 key 名与 Android 一致（抽 10 个 key 断言）。**不得在测试或工具里对 .env.local 的真实服务器做写操作。**
</task>
