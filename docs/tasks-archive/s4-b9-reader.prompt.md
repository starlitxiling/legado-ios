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
目标：阶段 4 单元 B9 —— 阅读器进阶：标题样式（对齐 / 字号倍数 / 上下边距）、字体选择（系统字体 + 导入 ttf/otf 文件）、翻页动画（覆盖 / 仿真 / 滚动 / 无动画，滑动与点击区域）、自动阅读（按速率滚动或翻页）、书签界面、高亮与批注（BookHighlight）、段评（ReviewRule，仅规则求值与展示，无发帖）、章节缓存进度显示。
工作目录：/Users/wujie/Work/legado-ios/.claude/worktrees/ios。工程：App/（XcodeGen 按目录收集，**不要运行 xcodegen、不改 project.yml / .xcodeproj**；新文件放 App/Sources/Features/<功能>/ 或 App/Sources/Shared/）；LegadoCore 在 Packages/LegadoCore（可新增目录与 public 入口，尽量不改既有文件；改动逐处列出）。已有能力：AnalyzeRule 引擎、AnalyzeUrlExecutor（含 webView 分支）、JsEngine/JavaHost、WebBook、Storage（Repository、AppDatabase.write、Migrations v1–v3、SourceStateRepository）、Entities、Network、Login/（SourceScriptBridge）、CheckSource/、LocalBook/（TXT / EPUB / MOBI / PDF）、Explore/、Images/、Backup/、WebView/、JsSource/、TTS/、Content/ContentProcessor；App 端 Features/{Bookshelf,Sources,ReplaceRules,Search,BookDetail,Toc,Reader,Settings,Backup,Explore,SourceLogin,CheckSource,LocalImport,Browser,ReadAloud}、Shared/{Theme,EmptyStateView,KeychainStore,RemoteImage,HeadlessWebView}。ViewModel 与纯逻辑放不 import UIKit / SwiftUI 的文件，用 @Observable；单测走 tools/appcore-check（追加自己的目标，软链引用 App 下非 UI 文件）与 LegadoCore 测试。你不能跑 xcodebuild（主会话代跑）。并行任务会改其他目录与 RootTabView / AppContainer / JavaHost / Reader 的不同区域：改共享文件前重新读取、只做最小局部插入、不重写。**验证一律在工作区内，不在 /tmp 做隔离副本**；swift test 用 CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/clang-cache" TMPDIR="$PWD/.build/tmp"（先 mkdir -p .build/tmp）--cache-path "$PWD/.build/cache" --disable-sandbox --disable-automatic-resolution --skip-update；磁盘只有约 3 GB，节省，不留大日志。Kotlin 只读，commit 2bdd3c58b，路径前缀 /Users/wujie/Work/legado-ios/app/src/main/java/io/legado/app/。Swift 语言模式 5；不加第三方依赖；不 commit；不联网。TDD 先红后绿；报告附命令与末尾 10 行、测试总数。汇报格式：中文 markdown ≤ 60 行。
Kotlin 规格：help/config/ReadBookConfig.kt（Config 字段全集：titleMode/titleSize/titleTopSpacing/titleBottomSpacing、textFont、pageAnim、paragraphIndent、lineSpacingExtra、paddings、autoReadSpeed、hideStatusBar 等；样式主题列表与 shared 项）、ui/book/read/page/{PageView,ReadView}.kt 与 page/delegate/{CoverPageDelegate,SimulationPageDelegate,ScrollPageDelegate,NoAnimPageDelegate}.kt（触摸区域九宫格、动画切换）、ui/book/read/page/provider/{ChapterProvider,TextChapterLayout}.kt（标题段落排版与已有 CoreText 分页对照）、ui/book/read/ReadBookActivity.kt 的自动阅读（autoPage）逻辑、ui/book/bookmark/BookmarkViewModel.kt 与 data/entities/Bookmark.kt、data/entities/BookHighlight.kt 与 ui/book/read/page/HighlightHelper（若存在）、data/entities/ReviewRule.kt 与 model/webBook/BookReview（若存在，不存在则在报告写明并只做实体 + 规则求值）、help/book/BookHelp.kt 的缓存判定（hasContent）用于目录页缓存标记。
产出：
1. LegadoCore：Reader/ReadBookConfig.swift（Codable 全字段 + 默认值对齐 Kotlin，导入 / 导出主题 JSON）、Reader/Highlight 实体与 Storage 表 / 迁移 v5（BookHighlight、ReviewRule 若为实体；Bookmark 已有则只补缺字段）+ Repository、Content/ 补标题排版参数（标题独立字号 / 对齐 / 间距）进入现有 CoreText 分页器（改动逐处列出）。
2. App：Features/Reader 下 PageAnimation/{CoverPageTransition,SimulationPageTransition,ScrollPageContainer,NoAnimTransition}（SwiftUI + UIKit 桥接或纯 SwiftUI，触摸九宫格与 Kotlin 一致）、AutoRead 控制器、FontPicker（系统字体列表 + 文件导入到 Application Support/fonts 并用 CTFontManagerRegisterFontsForURL 注册）、BookmarkListView、Highlight 选区菜单（高亮 / 批注 / 复制 / 朗读入口）、Toc 页缓存标记（已缓存章节打点）。ReadAloud 与 Reader 的既有接入不要重写，只局部插入。
3. 测试：ReadBookConfig 默认值与 JSON round-trip、九宫格触摸区域到动作的映射表、自动阅读速率到步进的换算（对齐 Kotlin autoReadSpeed 语义）、标题排版参数进入分页结果（标题占位行数随字号倍数变化）、高亮区间与章节偏移的持久化 round-trip、缓存标记判定。
</task>
