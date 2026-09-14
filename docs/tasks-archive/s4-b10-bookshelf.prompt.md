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
目标：阶段 4 单元 B10 —— 书架进阶与下载：分组编辑（增删改、排序、书籍多选移组）、书籍信息编辑（名 / 作者 / 封面 / 简介 / 自定义字段）、更新章节（前台并发刷新 + BGAppRefreshTask 后台刷新）、缓存整本 / 指定范围下载（并发与失败重试）、导出 TXT / EPUB（含替换规则开关、章节范围、EPUB 元数据与封面）。
工作目录：/Users/wujie/Work/legado-ios/.claude/worktrees/ios。工程：App/（XcodeGen 按目录收集，**不要运行 xcodegen、不改 project.yml / .xcodeproj**；新文件放 App/Sources/Features/<功能>/ 或 App/Sources/Shared/）；LegadoCore 在 Packages/LegadoCore（可新增目录与 public 入口，尽量不改既有文件；改动逐处列出）。已有能力：AnalyzeRule 引擎、AnalyzeUrlExecutor（含 webView 分支）、JsEngine/JavaHost、WebBook、Storage（Repository、AppDatabase.write、Migrations v1–v3、SourceStateRepository）、Entities、Network、Login/（SourceScriptBridge）、CheckSource/、LocalBook/（TXT / EPUB / MOBI / PDF）、Explore/、Images/、Backup/、WebView/、JsSource/、TTS/、Content/ContentProcessor；App 端 Features/{Bookshelf,Sources,ReplaceRules,Search,BookDetail,Toc,Reader,Settings,Backup,Explore,SourceLogin,CheckSource,LocalImport,Browser,ReadAloud}、Shared/{Theme,EmptyStateView,KeychainStore,RemoteImage,HeadlessWebView}。ViewModel 与纯逻辑放不 import UIKit / SwiftUI 的文件，用 @Observable；单测走 tools/appcore-check（追加自己的目标，软链引用 App 下非 UI 文件）与 LegadoCore 测试。你不能跑 xcodebuild（主会话代跑）。并行任务会改其他目录与 RootTabView / AppContainer / JavaHost / Reader 的不同区域：改共享文件前重新读取、只做最小局部插入、不重写。**验证一律在工作区内，不在 /tmp 做隔离副本**；swift test 用 CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/clang-cache" TMPDIR="$PWD/.build/tmp"（先 mkdir -p .build/tmp）--cache-path "$PWD/.build/cache" --disable-sandbox --disable-automatic-resolution --skip-update；磁盘只有约 3 GB，节省，不留大日志。Kotlin 只读，commit cb664b84d，路径前缀 /Users/wujie/Work/legado-ios/app/src/main/java/io/legado/app/。Swift 语言模式 5；不加第三方依赖；不 commit；不联网。TDD 先红后绿；报告附命令与末尾 10 行、测试总数。汇报格式：中文 markdown ≤ 60 行。
Kotlin 规格：ui/main/bookshelf/*（分组 tab、排序方式 bookshelfSort、更新标记）、ui/book/group/GroupViewModel.kt 与 data/entities/BookGroup.kt（内置分组 id 语义：全部 / 本地 / 音频 / 网络 / 未分组 / 未读 / 已读 / 错误 的位标识）、ui/book/info/edit/BookInfoEditViewModel.kt、service/CacheBookService.kt 与 model/CacheBook.kt（下载队列、并发数、失败重试、进度回调）、help/book/BookHelp.kt（章节缓存文件命名与存取、hasContent、formatChapterName）、ui/book/cache/CacheViewModel.kt 与 model/localBook/ 的导出（help/book/BookExport 或 ui/book/cache/CacheViewModel 内的 exportTxt / exportEpub，含 EPUB 打包结构 mimetype / META-INF / OEBPS）、ui/main/MainViewModel.kt 的 upToc 并发更新逻辑。
产出：
1. LegadoCore：Cache/{CacheBook.swift（下载队列 actor：按书按章、并发上限、重试、进度），BookExporter.swift（TXT 与 EPUB 导出，EPUB 用已有 ZipReader 的反向写入或自实现 store 模式 zip，字段顺序与文件布局对齐 Kotlin）}、Storage 补 BookGroup 完整字段与内置分组判定、Repository 补批量移组 / 更新标记；BookHelp 缓存命名对齐。
2. App：Features/Bookshelf 下 GroupEditView、多选模式（移组 / 删除 / 更新 / 缓存）、BookInfoEditView（Features/BookDetail/Edit）、Features/Download/{DownloadCenterModel,DownloadCenterView}（进度、暂停、取消）、Export 入口（章节范围选择 + ShareLink）、AppContainer 注册 BGAppRefreshTask（标识符写在 Info.plist 的 BGTaskSchedulerPermittedIdentifiers —— 你不能改 project.yml，报告里写明需要主会话加 `BGTaskSchedulerPermittedIdentifiers: [io.legado.ios.refresh]` 与 `UIBackgroundModes` 追加 fetch）。
3. 测试：内置分组位判定（对齐 Kotlin BookGroup 常量）、下载队列并发与重试状态机（假 WebBook 注入）、TXT 导出内容与章节格式（替换规则开 / 关）、EPUB 导出包结构（mimetype 首项且 stored、container.xml、OPF manifest / spine 顺序、封面）、更新章节的并发上限与失败隔离、书籍编辑保存的字段覆盖规则。
</task>
