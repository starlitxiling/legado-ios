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
目标：阶段 4 单元 B2 —— 书源登录（网页 / 表单）、Cookie 管理、书源校验。
工作目录：/Users/wujie/Work/legado-ios/.claude/worktrees/ios。工程：App/（XcodeGen 按目录收集，**不要运行 xcodegen、不改 project.yml / .xcodeproj**；新文件放 App/Sources/Features/<功能>/ 或 App/Sources/Shared/）；LegadoCore 在 Packages/LegadoCore（可新增目录与 public 入口，尽量不改既有文件；改动逐处列出）。已有：AppContainer（依赖容器）、RootTabView、Features/{Bookshelf,Sources,ReplaceRules,Search,BookDetail,Toc,Reader,Settings,Backup}、Shared/{Theme,EmptyStateView,KeychainStore}；LegadoCore 的 AnalyzeRule 引擎、AnalyzeUrlExecutor、JsEngine/JavaHost、WebBook、Storage（Repository + AppDatabase.write 事务）、Entities、Import、Network（HttpClient / BoundedURLSessionHttpClient / ReplayHttpClient / CookieStore）、Backup。ViewModel 与纯逻辑放不 import UIKit / SwiftUI 的文件，用 @Observable；单测走 tools/appcore-check（追加自己的目标，软链引用 App 下非 UI 文件）与 LegadoCore 测试。你不能跑 xcodebuild（主会话代跑），但 SwiftUI 文件要保证语法与 API 正确。其他并行任务会改别的 Features 目录与 RootTabView / AppContainer 的不同区域：改这两个文件前重新读取、只做最小局部插入、不重写。Kotlin 只读，commit 2bdd3c58b，路径前缀 /Users/wujie/Work/legado-ios/app/src/main/java/io/legado/app/。Swift 语言模式 5；不加第三方依赖；不 commit；不联网。TDD 先红后绿；完成后跑 LegadoCore 全量与 appcore-check 相关目标的 swift test（并行任务半成品导致失败时用隔离副本并说明），贴命令与末尾 10 行、测试总数。汇报格式：中文 markdown ≤ 60 行。
Kotlin 规格：model/login/*（LoginUi 表单定义、loginCheckJs、getVariable / setVariable / getLoginHeader / getLoginInfo / putLoginInfo、login() 脚本注入）、data/entities/BaseSource.kt 的登录相关方法与 loginHeader、help/http/CookieStore.kt 与 CookieManager（网页登录后 Cookie 回写）、ui/login/{WebViewLoginActivity,SourceLoginActivity}（网页登录：WKWebView 打开 loginUrl，用户登录后取该域 Cookie 写入 CookieStore；表单登录：按 loginUi 渲染输入项，提交时执行 loginJs）、model/CheckSource.kt + service/CheckSourceService.kt（校验流程：搜索关键词 → 详情 → 目录 → 正文，逐步记录耗时与错误，写回 BookSource.respondTime / 错误信息与 BookSourceCheckState）。
产出：
1. LegadoCore：Login/SourceLogin.swift（loginUi 解析、login() 脚本执行、loginCheckJs、变量存取走 Storage 的 Cookie / 变量表——若缺表在 Storage 下新增迁移 v2 并保持向后兼容）、CheckSource/SourceChecker.swift（可注入 HttpClient，逐步骤结果模型）。
2. App：Features/SourceLogin/{WebLoginView（WKWebView + 完成按钮回写 Cookie）,FormLoginView,SourceLoginViewModel}.swift；Features/CheckSource/{CheckSourceViewModel,CheckSourceView}.swift（批量校验、进度、结果着色、失败原因）；书源列表行加入「登录」「校验」入口（Features/Sources 的最小改动，重新读取后局部插入）；Cookie 管理页（按域列出 / 清除）。
3. 测试：loginUi 解析与提交脚本、loginCheckJs 判定、Cookie 回写、校验流程各步骤成功 / 失败 / 超时（ReplayHttpClient + fixtures/webbook 自造站点）。
</task>
