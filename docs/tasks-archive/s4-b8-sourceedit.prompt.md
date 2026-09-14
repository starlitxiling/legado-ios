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
目标：阶段 4 单元 B8 —— 书源编辑与管理进阶：书源编辑器（全字段表单 + JSON 编辑 + 调试面板）、分组 / 排序 / 批量启停 / 置顶置底、导出与分享（JSON 文件、二维码）、替换规则编辑器、TXT 目录规则与字典规则管理。
工作目录：/Users/wujie/Work/legado-ios/.claude/worktrees/ios。工程：App/（XcodeGen 按目录收集，**不要运行 xcodegen、不改 project.yml / .xcodeproj**；新文件放 App/Sources/Features/<功能>/ 或 App/Sources/Shared/）；LegadoCore 在 Packages/LegadoCore（可新增目录与 public 入口，尽量不改既有文件；改动逐处列出）。已有能力：AnalyzeRule 引擎、AnalyzeUrlExecutor（含 webView 分支）、JsEngine/JavaHost、WebBook、Storage（Repository、AppDatabase.write、Migrations v1–v3、SourceStateRepository）、Entities、Network、Login/（SourceScriptBridge）、CheckSource/、LocalBook/（TXT / EPUB / MOBI / PDF）、Explore/、Images/、Backup/、WebView/、JsSource/、TTS/、Content/ContentProcessor；App 端 Features/{Bookshelf,Sources,ReplaceRules,Search,BookDetail,Toc,Reader,Settings,Backup,Explore,SourceLogin,CheckSource,LocalImport,Browser,ReadAloud}、Shared/{Theme,EmptyStateView,KeychainStore,RemoteImage,HeadlessWebView}。ViewModel 与纯逻辑放不 import UIKit / SwiftUI 的文件，用 @Observable；单测走 tools/appcore-check（追加自己的目标，软链引用 App 下非 UI 文件）与 LegadoCore 测试。你不能跑 xcodebuild（主会话代跑）。并行任务会改其他目录与 RootTabView / AppContainer / JavaHost / Reader 的不同区域：改共享文件前重新读取、只做最小局部插入、不重写。**验证一律在工作区内，不在 /tmp 做隔离副本**；swift test 用 CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/clang-cache" TMPDIR="$PWD/.build/tmp"（先 mkdir -p .build/tmp）--cache-path "$PWD/.build/cache" --disable-sandbox --disable-automatic-resolution --skip-update；磁盘只有约 3 GB，节省，不留大日志。Kotlin 只读，commit 2bdd3c58b，路径前缀 /Users/wujie/Work/legado-ios/app/src/main/java/io/legado/app/。Swift 语言模式 5；不加第三方依赖；不 commit；不联网。TDD 先红后绿；报告附命令与末尾 10 行、测试总数。汇报格式：中文 markdown ≤ 60 行。
Kotlin 规格：ui/book/source/edit/BookSourceEditViewModel.kt（字段分组、保存校验、JSON 粘贴导入、登录 / 校验入口）、ui/book/source/manage/BookSourceViewModel.kt（启停、置顶置底、分组增删、排序方式、导出 / 分享、检索）、ui/book/source/debug/BookSourceDebugModel.kt 与 model/Debug.kt（调试日志流：搜索 / 详情 / 目录 / 正文四段，日志格式与时间戳）、ui/replace/edit/ReplaceEditViewModel.kt 与 ui/replace/ReplaceRuleViewModel.kt、data/entities/{TxtTocRule,DictRule}.kt 与 ui/book/toc/rule/TxtTocRuleViewModel.kt、ui/dict/rule/DictRuleViewModel.kt、help/DefaultData.kt（内置默认 TXT 目录规则与字典规则 assets）、utils/QRCodeUtils（生成用 CoreImage CIQRCodeGenerator）。
产出：
1. LegadoCore：Debug/SourceDebugger.swift（复刻 model/Debug 的四段流程与日志行格式，可注入 HttpClient，日志经 AsyncStream 输出）；Entities 补 TxtTocRule、DictRule 与 Storage 表 / 迁移 v4 + Repository（已有 ReplaceRule 表不变）；内置默认规则用合成最小集（不复制 Android assets 中第三方内容，只保留结构与 1–2 条通用规则）；Export/SourceExporter.swift（书源 / 替换规则导出 JSON，字段顺序与 Kotlin GsonExtensions 一致，null 字段省略规则回源）。
2. App：Features/Sources/Edit/{BookSourceEditModel,BookSourceEditView}（按 Kotlin 字段分组：基本 / 搜索 / 发现 / 详情 / 目录 / 正文 / 登录，每组 TextField，JSON 模式用 TextEditor 双向同步）、Features/Sources/Debug/{SourceDebugModel,SourceDebugView}、Sources 列表页补分组筛选 / 排序菜单 / 多选批量启停 / 置顶置底 / 导出 ShareLink / 二维码弹窗；Features/ReplaceRules/Edit/{ReplaceRuleEditModel,ReplaceRuleEditView}；Features/Settings 下新增 TxtTocRules 与 DictRules 管理页（列表 / 启停 / 编辑 / 导入 JSON）。
3. 测试：SourceDebugger 日志格式与四段顺序（ReplayHttpClient）、导出 JSON round-trip 与字段顺序、编辑模型的校验（bookSourceUrl 必填、重复 URL、JSON 粘贴解析）、排序比较器（按名称 / 权重 / 更新时间 / 响应时间对齐 Kotlin）、批量启停与置顶置底对 customOrder 的影响。
</task>
