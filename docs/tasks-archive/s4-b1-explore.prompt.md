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
目标：阶段 4 单元 B1 —— 发现页、封面加载、正文图片。
工作目录：/Users/wujie/Work/legado-ios/.claude/worktrees/ios。工程：App/（XcodeGen 按目录收集，**不要运行 xcodegen、不改 project.yml / .xcodeproj**；新文件放 App/Sources/Features/<功能>/ 或 App/Sources/Shared/）；LegadoCore 在 Packages/LegadoCore（可新增目录与 public 入口，尽量不改既有文件；改动逐处列出）。已有：AppContainer（依赖容器）、RootTabView、Features/{Bookshelf,Sources,ReplaceRules,Search,BookDetail,Toc,Reader,Settings,Backup}、Shared/{Theme,EmptyStateView,KeychainStore}；LegadoCore 的 AnalyzeRule 引擎、AnalyzeUrlExecutor、JsEngine/JavaHost、WebBook、Storage（Repository + AppDatabase.write 事务）、Entities、Import、Network（HttpClient / BoundedURLSessionHttpClient / ReplayHttpClient / CookieStore）、Backup。ViewModel 与纯逻辑放不 import UIKit / SwiftUI 的文件，用 @Observable；单测走 tools/appcore-check（追加自己的目标，软链引用 App 下非 UI 文件）与 LegadoCore 测试。你不能跑 xcodebuild（主会话代跑），但 SwiftUI 文件要保证语法与 API 正确。其他并行任务会改别的 Features 目录与 RootTabView / AppContainer 的不同区域：改这两个文件前重新读取、只做最小局部插入、不重写。Kotlin 只读，commit cb664b84d，路径前缀 /Users/wujie/Work/legado-ios/app/src/main/java/io/legado/app/。Swift 语言模式 5；不加第三方依赖；不 commit；不联网。TDD 先红后绿；完成后跑 LegadoCore 全量与 appcore-check 相关目标的 swift test（并行任务半成品导致失败时用隔离副本并说明），贴命令与末尾 10 行、测试总数。汇报格式：中文 markdown ≤ 60 行。
Kotlin 规格：model/webBook/BookList.kt 的 explore 分支与 data/entities/rule/ExploreRule.kt、data/entities/BookSource.kt 的 exploreUrl 解析（exploreKinds：换行 / :: 分隔、JSON 数组形态、分组标题、<js> 动态发现、{{page}} 分页、exploreScreen）；help/book/BookHelp.kt saveImage / getImage（图片缓存目录与命名、按书源 header 与 cookie 下载、coverDecodeJs / imageDecode 解密）；model/ImageProvider.kt（正文图片解码显示）；help/glide 的封面加载语义（占位、失败回退）；ui/book/explore、ui/main/explore（发现 Tab 的书源列表、分类、书单）。
产出：
1. LegadoCore：Explore/ExploreKinds.swift（解析发现分类，含 JS 动态分类）、WebBook 的 explore 入口（若已有则补齐分页与 exploreScreen）、Images/ImageDownloader.swift（按书源 header / cookie 下载、缓存到 Caches/legado/images/<hash>、imageDecode / coverDecodeJs 解密）。
2. App：Features/Explore/{ExploreViewModel,ExploreView,ExploreBookListView}.swift（书源分类列表、点击分类拉书单分页、加入书架 / 进详情）；Shared/RemoteImage.swift（异步封面视图：缓存优先、占位、失败回退）；书架 / 搜索 / 详情接入封面；Reader：正文图片（<img> 占位分页 + 异步下载后渲染，先做「图片单独占一页 / 段」的最简排版，注明限制）。
3. RootTabView 增加「发现」入口（放搜索 Tab 内的分段或独立 Tab，按 Android 的主页结构：书架 / 发现 / 订阅 / 我的；本单元只加发现）。
4. 测试：exploreKinds 各形态解析、发现分页、图片下载缓存与解密（ReplayHttpClient）、封面视图模型状态。
</task>
