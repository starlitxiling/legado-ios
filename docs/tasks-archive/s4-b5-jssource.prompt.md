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
目标：阶段 4 单元 B5 —— 纯 JS 书源（mainJs）：JsSourceConfig.extract 识别与解析、JsSourceEngine 执行（search / explore / bookInfo / toc / content 等函数约定）、与 WebBook 流程和导入的接入。
工作目录：/Users/wujie/Work/legado-ios/.claude/worktrees/ios。工程：App/（XcodeGen 按目录收集，**不要运行 xcodegen、不改 project.yml / .xcodeproj**；新文件放 App/Sources/Features/<功能>/ 或 App/Sources/Shared/）；LegadoCore 在 Packages/LegadoCore（可新增目录与 public 入口，尽量不改既有文件；改动逐处列出）。已有能力：AnalyzeRule 引擎、AnalyzeUrlExecutor（webView 分支目前抛未实现）、JsEngine/JavaHost（webView* 方法为桩）、WebBook、Storage（Repository、AppDatabase.write、SourceStateRepository）、Entities、Network、Login/、CheckSource/、LocalBook/（TXT / EPUB、ZipReader）、Explore/、Images/、Backup/；App 端 Features/{Bookshelf,Sources,ReplaceRules,Search,BookDetail,Toc,Reader,Settings,Backup,Explore,SourceLogin,CheckSource,LocalImport}、Shared/{Theme,EmptyStateView,KeychainStore,RemoteImage}。ViewModel 与纯逻辑放不 import UIKit / SwiftUI 的文件，用 @Observable；单测走 tools/appcore-check（追加自己的目标，软链引用 App 下非 UI 文件）与 LegadoCore 测试。你不能跑 xcodebuild（主会话代跑）。并行任务会改其他目录与 RootTabView / AppContainer / JavaHost 的不同区域：改共享文件前重新读取、只做最小局部插入、不重写。**验证一律在工作区内，不在 /tmp 做隔离副本**；swift test 用 CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/clang-cache" TMPDIR="$PWD/.build/tmp"（目录已存在）--cache-path "$PWD/.build/cache" --disable-sandbox --disable-automatic-resolution --skip-update；磁盘只有约 3 GB，节省。Kotlin 只读，commit cb664b84d，路径前缀 /Users/wujie/Work/legado-ios/app/src/main/java/io/legado/app/。Swift 语言模式 5；不加第三方依赖；不 commit；不联网。TDD 先红后绿；报告附命令与末尾 10 行、测试总数。汇报格式：中文 markdown ≤ 60 行。
Kotlin 规格：model/jsSource/*（7 个文件 1378 行：JsSourceConfig（从纯 JS 文本抽取配置头：书源名 / URL / 版本等注释或导出对象）、JsSourceEngine（:107-114 的绑定：java / source / sourceApi / baseUrl / cookie / cache + 调用参数；各入口函数名与返回结构约定、错误处理）、JsSourceRuntime 等）、ImportBookSourceViewModel.kt:284 的 extract 入口、data/entities/BookSource.kt 的 mainJs 字段。
产出：
1. LegadoCore：JsSource/{JsSourceConfig,JsSourceEngine,JsSourceApi}.swift（用已有 JsEngine，绑定与 Kotlin 一致；返回结构映射到 SearchBook / Book / BookChapter / 正文）；WebBook 四条流程在书源含 mainJs 时分流到引擎；Import/SourceImporter 把「纯 JS 文本」与「JSON 里含 mainJs」都解析为可用书源（去掉 unsupported 标记）。
2. App：书源导入预览与列表显示「JS 书源」标记；不需要新页面。
3. 测试：合成的最小纯 JS 书源（自造函数、example.invalid）走导入 → 搜索 → 详情 → 目录 → 正文；配置头抽取的各形态；错误函数 / 缺函数的行为按 Kotlin。
</task>
