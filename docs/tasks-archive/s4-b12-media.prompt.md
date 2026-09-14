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
目标：阶段 4 单元 B12 —— 漫画 / 音频源：bookSourceType 1 音频（章节 URL 求值为音频地址，AVPlayer 播放、后台播放、锁屏控制、进度记忆、定时）、2 图片 / 漫画（正文为图片 URL 列表，漫画阅读器：竖向连续 / 横向翻页、预加载、缩放、图片 header / decode 规则）、3 视频只做类型识别与占位提示。
工作目录：/Users/wujie/Work/legado-ios/.claude/worktrees/ios。工程：App/（XcodeGen 按目录收集，**不要运行 xcodegen、不改 project.yml / .xcodeproj**；新文件放 App/Sources/Features/<功能>/ 或 App/Sources/Shared/）；LegadoCore 在 Packages/LegadoCore（可新增目录与 public 入口，尽量不改既有文件；改动逐处列出）。已有能力：AnalyzeRule 引擎、AnalyzeUrlExecutor（含 webView 分支）、JsEngine/JavaHost、WebBook、Storage（Repository、AppDatabase.write、Migrations v1–v3、SourceStateRepository）、Entities、Network、Login/（SourceScriptBridge）、CheckSource/、LocalBook/（TXT / EPUB / MOBI / PDF）、Explore/、Images/、Backup/、WebView/、JsSource/、TTS/、Content/ContentProcessor、Reader/、Debug/、Export/、Cache/（CacheBook、BookExporter、BookHelp）；App 端 Features/{Bookshelf,Sources,ReplaceRules,Search,BookDetail,Toc,Reader,Settings,Backup,Explore,SourceLogin,CheckSource,LocalImport,Browser,ReadAloud,Download}、Shared/{Theme,EmptyStateView,KeychainStore,RemoteImage,HeadlessWebView}。ViewModel 与纯逻辑放不 import UIKit / SwiftUI 的文件，用 @Observable；单测走 tools/appcore-check（追加自己的目标，软链引用 App 下非 UI 文件）与 LegadoCore 测试。你不能跑 xcodebuild（主会话代跑）。并行任务会改其他目录与 RootTabView / AppContainer / JavaHost / Reader / Settings / BackupImporter 的不同区域：改共享文件前重新读取、只做最小局部插入、不重写。**验证一律在工作区内，不在 /tmp 做隔离副本**；swift test 用 CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/clang-cache" TMPDIR="$PWD/.build/tmp"（先 mkdir -p .build/tmp）--cache-path "$PWD/.build/cache" --disable-sandbox --disable-automatic-resolution --skip-update；磁盘只有约 3 GB，节省，不留大日志。Kotlin 只读，commit cb664b84d，路径前缀 /Users/wujie/Work/legado-ios/app/src/main/java/io/legado/app/。Swift 语言模式 5；不加第三方依赖；不 commit；不联网。TDD 先红后绿；报告附命令与末尾 10 行、测试总数。汇报格式：中文 markdown ≤ 60 行。
Kotlin 规格：data/entities/BookSource.kt 与 constant/BookType.kt（type 位标识：text 8 / audio 32 / image 64 / video ... 回源确切常量与 isAudio / isImage 判定）、model/webBook/BookContent.kt 与 help/book/BookHelp.kt 的图片类型分支（正文按行拆图片 URL、`<img src>` 提取、图片 URL 的 header 附加 {{...}} 语法）、service/AudioPlayService.kt 与 model/AudioPlay.kt（状态机 play / pause / stop / next / prev、进度保存 durChapterPos、上一曲 / 下一曲、播放 URL 求值含 headers、超时与错误重试、定时停止）、ui/book/audio/AudioPlayViewModel.kt、ui/book/manga/{ReadMangaActivity,ReadMangaViewModel}.kt（图片列表加载、预加载数量、章节切换、进度）、model/ImageProvider.kt（图片缓存与 decode 规则、并发限制）。
产出：
1. LegadoCore：Media/{AudioPlayEngine.swift（状态机 + 可注入 Player protocol，不依赖 AVFoundation）,MediaContentResolver.swift（音频地址求值、漫画图片列表提取与 header 解析）}，Entities / WebBook 的 type 判定补齐（改动逐处列出）。
2. App：Features/AudioPlay/{AVPlayerAudioPlayer.swift（AVPlayer 实现 Player，AVAudioSession、MPRemoteCommandCenter、NowPlaying，与既有 ReadAloud 的音频会话互斥：开始播放时停止朗读）,AudioPlayView.swift}、Features/Manga/{MangaReaderView.swift（LazyVStack 连续 / TabView 横向，预加载 N 张，双指缩放）,MangaReaderModel.swift}；BookDetail / Bookshelf 入口按 type 分流到音频 / 漫画 / 文本阅读器（最小插入）；视频类型给占位提示。
3. 测试：type 位判定、音频状态机（播放 / 暂停 / 切章 / 章末自动下一章 / 定时 / 错误重试）、图片列表提取（含 `<img>`、纯 URL 行、带 header 的 {{}} 语法）、漫画进度记忆、预加载窗口计算。
</task>
