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
目标：阶段 4 单元 B4 —— WebView 抓取：BackstageWebView 语义（useWebView 请求、@webjs: 规则、java.webView / webViewGetSource / webViewGetOverrideUrl、getVerificationCode、startBrowser / startBrowserAwait），WKWebView 挂在 key window 上零尺寸运行、仅前台、超时与并发上限。
工作目录：/Users/wujie/Work/legado-ios/.claude/worktrees/ios。工程：App/（XcodeGen 按目录收集，**不要运行 xcodegen、不改 project.yml / .xcodeproj**；新文件放 App/Sources/Features/<功能>/ 或 App/Sources/Shared/）；LegadoCore 在 Packages/LegadoCore（可新增目录与 public 入口，尽量不改既有文件；改动逐处列出）。已有能力：AnalyzeRule 引擎、AnalyzeUrlExecutor（webView 分支目前抛未实现）、JsEngine/JavaHost（webView* 方法为桩）、WebBook、Storage（Repository、AppDatabase.write、SourceStateRepository）、Entities、Network、Login/、CheckSource/、LocalBook/（TXT / EPUB、ZipReader）、Explore/、Images/、Backup/；App 端 Features/{Bookshelf,Sources,ReplaceRules,Search,BookDetail,Toc,Reader,Settings,Backup,Explore,SourceLogin,CheckSource,LocalImport}、Shared/{Theme,EmptyStateView,KeychainStore,RemoteImage}。ViewModel 与纯逻辑放不 import UIKit / SwiftUI 的文件，用 @Observable；单测走 tools/appcore-check（追加自己的目标，软链引用 App 下非 UI 文件）与 LegadoCore 测试。你不能跑 xcodebuild（主会话代跑）。并行任务会改其他目录与 RootTabView / AppContainer / JavaHost 的不同区域：改共享文件前重新读取、只做最小局部插入、不重写。**验证一律在工作区内，不在 /tmp 做隔离副本**；swift test 用 CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/clang-cache" TMPDIR="$PWD/.build/tmp"（目录已存在）--cache-path "$PWD/.build/cache" --disable-sandbox --disable-automatic-resolution --skip-update；磁盘只有约 3 GB，节省。Kotlin 只读，commit 2bdd3c58b，路径前缀 /Users/wujie/Work/legado-ios/app/src/main/java/io/legado/app/。Swift 语言模式 5；不加第三方依赖；不 commit；不联网。TDD 先红后绿；报告附命令与末尾 10 行、测试总数。汇报格式：中文 markdown ≤ 60 行。
Kotlin 规格：help/http/BackstageWebView.kt（398 行：参数 url / html / tag / sourceRegex / overrideUrlRegex / javaScript / delayTime / cacheFirst / result / isRule；加载完成后延时执行 JS 取 document 或匹配 sourceRegex 的资源响应；overrideUrlRegex 拦截跳转；结果返回 StrResponse）、model/analyzeRule/AnalyzeUrl.kt 的 webView 分支（:482 附近）、AnalyzeRule.kt 的 WebJs 模式（:187）、help/JsExtensions.kt 的 webView* / getVerificationCode / startBrowser（:279-442）、ui/browser 与验证码对话框。
产出：
1. LegadoCore：WebView/HeadlessWebViewProtocol.swift（protocol：load(url|html, headers, cookies, javaScript, delayTime, sourceRegex, overrideUrlRegex, timeout) async → StrResponse；LegadoCore 只定义协议与调度器 HeadlessWebViewScheduler（并发上限、超时、前台检查钩子）），AnalyzeUrlExecutor 与 AnalyzeRule 的 webView / WebJs 分支接入协议，JavaHost 的 webView* / getVerificationCode / startBrowser 走协议（getVerificationCode 与 startBrowser 需要 UI 交互，定义 UserInteraction protocol 由 App 注入）。
2. App：Shared/HeadlessWebView.swift（WKWebView 实现：挂到 key window 零尺寸、WKUserContentController 注入 JS、资源拦截用 WKURLSchemeHandler 或 JS 侧 fetch 拦截来匹配 sourceRegex——回源 Kotlin 是用 shouldInterceptRequest 拦截资源响应，iOS 无等价物，说明你的替代方案与局限）、Cookie 同步到 CookieStore；Features/Browser/{BrowserView（startBrowser 打开的页面，含完成回调）,VerificationCodeView}；AppContainer 注入。
3. 测试：调度器并发 / 超时 / 前台钩子；协议假实现下 AnalyzeUrl webView 分支、@webjs: 规则、java.webView 的返回；文档 docs/spec/network-compat.md 更新 WebView 一节（能力与差异）。
</task>
