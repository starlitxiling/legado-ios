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
目标：阶段 4 单元 B3 —— 本地书 TXT 与 EPUB：导入、解析、目录、正文，接入书架与阅读器。
工作目录：/Users/wujie/Work/legado-ios/.claude/worktrees/ios。工程：App/（XcodeGen 按目录收集，**不要运行 xcodegen、不改 project.yml / .xcodeproj**；新文件放 App/Sources/Features/<功能>/ 或 App/Sources/Shared/）；LegadoCore 在 Packages/LegadoCore（可新增目录与 public 入口，尽量不改既有文件；改动逐处列出）。已有：AppContainer（依赖容器）、RootTabView、Features/{Bookshelf,Sources,ReplaceRules,Search,BookDetail,Toc,Reader,Settings,Backup}、Shared/{Theme,EmptyStateView,KeychainStore}；LegadoCore 的 AnalyzeRule 引擎、AnalyzeUrlExecutor、JsEngine/JavaHost、WebBook、Storage（Repository + AppDatabase.write 事务）、Entities、Import、Network（HttpClient / BoundedURLSessionHttpClient / ReplayHttpClient / CookieStore）、Backup。ViewModel 与纯逻辑放不 import UIKit / SwiftUI 的文件，用 @Observable；单测走 tools/appcore-check（追加自己的目标，软链引用 App 下非 UI 文件）与 LegadoCore 测试。你不能跑 xcodebuild（主会话代跑），但 SwiftUI 文件要保证语法与 API 正确。其他并行任务会改别的 Features 目录与 RootTabView / AppContainer 的不同区域：改这两个文件前重新读取、只做最小局部插入、不重写。Kotlin 只读，commit cb664b84d，路径前缀 /Users/wujie/Work/legado-ios/app/src/main/java/io/legado/app/。Swift 语言模式 5；不加第三方依赖；不 commit；不联网。TDD 先红后绿；完成后跑 LegadoCore 全量与 appcore-check 相关目标的 swift test（并行任务半成品导致失败时用隔离副本并说明），贴命令与末尾 10 行、测试总数。汇报格式：中文 markdown ≤ 60 行。
Kotlin 规格：model/localBook/LocalBook.kt（导入入口、书名作者从文件名解析 nameAuthor 正则、bookUrl 为文件 URI、origin=loc_book、type 位）、TextFile.kt（623 行：编码探测、按 TxtTocRule 正则分章、无规则时的默认规则与单章回退、章节 start/end 偏移、大文件分块读取、getContent 按偏移读取）、data/entities/TxtTocRule.kt 与 help/DefaultData 的内置目录规则（assets/defaultData/txtTocRule.json——请读 Android 仓库该 assets 文件并把内置规则作为 Swift 静态表移植）、EpubFile.kt（514 行：zip 读取修复、OPF 解析、NCX / nav 目录、spine 顺序、章节 HTML → 文本（保留段落与图片占位）、封面提取）、modules/book 里 epublib 的关键语义。已有可复用：Backup/BackupArchive.swift 的 zip 读取器（可抽成通用 ZipReader，改动逐处列出）、HtmlFormatter、SwiftSoup。
产出：
1. LegadoCore：LocalBook/{LocalBook,TextFileParser,TxtTocRule,EpubParser,ZipReader}.swift；Storage 增加 TxtTocRule 表（迁移 v2，向后兼容）与内置规则灌入；WebBook / 阅读取正文入口对本地书分流（bookUrl 为 file 且 origin=loc_book 时走本地解析）。
2. App：Features/LocalImport/{LocalImportViewModel,LocalImportView}.swift（UIDocumentPicker 多选 txt / epub，复制进沙盒 Documents/Books，security-scoped bookmark）、书架「导入本地书」入口、TXT 目录规则管理页（列表 / 启用 / 编辑正则）。
3. 测试：文件名解析、编码探测（UTF-8 / GBK / UTF-16 BOM 合成样本）、分章规则（内置规则对合成文本）、偏移读取、EPUB 合成样本（用 zip 生成脚本自造最小 EPUB）目录与正文。
</task>
