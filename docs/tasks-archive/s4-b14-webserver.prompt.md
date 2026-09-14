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
目标：阶段 4 单元 B14 —— 局域网 Web 服务：前台运行的 HTTP 服务（NWListener，端口默认 1122，可配置），提供 Android web/ 同名 API 与内置网页（modules/web 的构建产物已在 Android 仓 app/src/main/assets/web/ 下：只读参考其请求路径与响应 JSON 结构；**不复制其前端资源进本仓库**，内置页面用最小自写 HTML 列书架 / 书源 / 阅读即可）；WebSocket 书源调试与搜索接口（若工作量过大只做 HTTP 部分并写明）。
工作目录：/Users/wujie/Work/legado-ios/.claude/worktrees/ios。工程：App/（XcodeGen 按目录收集，**不要运行 xcodegen、不改 project.yml / .xcodeproj**；新文件放 App/Sources/Features/<功能>/ 或 App/Sources/Shared/）；LegadoCore 在 Packages/LegadoCore（可新增目录与 public 入口，尽量不改既有文件；改动逐处列出）。已有能力：AnalyzeRule 引擎、AnalyzeUrlExecutor（含 webView 分支）、JsEngine/JavaHost、WebBook、Storage（Repository、AppDatabase.write、Migrations v1–v3、SourceStateRepository）、Entities、Network、Login/（SourceScriptBridge）、CheckSource/、LocalBook/（TXT / EPUB / MOBI / PDF）、Explore/、Images/、Backup/、WebView/、JsSource/、TTS/、Content/ContentProcessor、Reader/、Debug/、Export/、Cache/（CacheBook、BookExporter、BookHelp）；App 端 Features/{Bookshelf,Sources,ReplaceRules,Search,BookDetail,Toc,Reader,Settings,Backup,Explore,SourceLogin,CheckSource,LocalImport,Browser,ReadAloud,Download}、Shared/{Theme,EmptyStateView,KeychainStore,RemoteImage,HeadlessWebView}。ViewModel 与纯逻辑放不 import UIKit / SwiftUI 的文件，用 @Observable；单测走 tools/appcore-check（追加自己的目标，软链引用 App 下非 UI 文件）与 LegadoCore 测试。你不能跑 xcodebuild（主会话代跑）。并行任务会改其他目录与 RootTabView / AppContainer / JavaHost / Reader / Settings / BackupImporter 的不同区域：改共享文件前重新读取、只做最小局部插入、不重写。**验证一律在工作区内，不在 /tmp 做隔离副本**；swift test 用 CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/clang-cache" TMPDIR="$PWD/.build/tmp"（先 mkdir -p .build/tmp）--cache-path "$PWD/.build/cache" --disable-sandbox --disable-automatic-resolution --skip-update；磁盘只有约 3 GB，节省，不留大日志。Kotlin 只读，commit 2bdd3c58b，路径前缀 /Users/wujie/Work/legado-ios/app/src/main/java/io/legado/app/。Swift 语言模式 5；不加第三方依赖；不 commit；不联网。TDD 先红后绿；报告附命令与末尾 10 行、测试总数。汇报格式：中文 markdown ≤ 60 行。
Kotlin 规格：web/{HttpServer,WebSocketServer}.kt（路由表：/getBookshelf、/getChapterList、/getBookContent、/saveBook、/deleteBook、/getBookSources、/getBookSource、/saveBookSource、/saveBookSources、/deleteBookSources、/getReplaceRules 等，回源全部路径与参数名）、web/controller/{BookController,SourceController,ReplaceRuleController,RssSourceController}.kt（返回 ReturnData 结构 isSuccess / errorMsg / data）、web/utils/ReturnData.kt、service/WebService.kt（启动 / 停止、通知、地址展示）、help/config/AppConfig.webPort。
产出：
1. LegadoCore：Web/{HttpRouter.swift（路径 → handler，纯逻辑可测）,WebApi.swift（各 controller 移植，依赖 Repository 与 WebBook）,ReturnData.swift}；HTTP 解析 / 响应最小实现（请求行、头、body、Content-Length、keep-alive 可不支持），基于 Network.framework NWListener（放 App 或 Core 均可，但路由与 controller 必须不依赖 Network 以便测试）。
2. App：Features/WebService/{WebServiceController.swift（启停、当前 IP 与端口展示、只在前台运行，进后台停止并提示）,WebServiceView.swift}；Settings 入口。
3. 测试：路由分派与参数解析、每个 controller 的成功 / 失败 ReturnData JSON 与 Android 字段名一致（用内存数据库）、HTTP 报文解析（合成请求字节）、内置页面 200 与 404。
</task>
