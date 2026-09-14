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
目标：阶段 4 单元 B7 —— 本地书 MOBI 与 PDF：MOBI 解析（移植 lib/mobi 纯逻辑）、PDF（PDFKit 提取文本按页分章）、接入 LocalBook 的导入 / 目录 / 正文分流。
工作目录：/Users/wujie/Work/legado-ios/.claude/worktrees/ios。工程：App/（XcodeGen 按目录收集，**不要运行 xcodegen、不改 project.yml / .xcodeproj**；新文件放 App/Sources/Features/<功能>/ 或 App/Sources/Shared/）；LegadoCore 在 Packages/LegadoCore（可新增目录与 public 入口，尽量不改既有文件；改动逐处列出）。已有能力：AnalyzeRule 引擎、AnalyzeUrlExecutor（webView 分支目前抛未实现）、JsEngine/JavaHost（webView* 方法为桩）、WebBook、Storage（Repository、AppDatabase.write、SourceStateRepository）、Entities、Network、Login/、CheckSource/、LocalBook/（TXT / EPUB、ZipReader）、Explore/、Images/、Backup/；App 端 Features/{Bookshelf,Sources,ReplaceRules,Search,BookDetail,Toc,Reader,Settings,Backup,Explore,SourceLogin,CheckSource,LocalImport}、Shared/{Theme,EmptyStateView,KeychainStore,RemoteImage}。ViewModel 与纯逻辑放不 import UIKit / SwiftUI 的文件，用 @Observable；单测走 tools/appcore-check（追加自己的目标，软链引用 App 下非 UI 文件）与 LegadoCore 测试。你不能跑 xcodebuild（主会话代跑）。并行任务会改其他目录与 RootTabView / AppContainer / JavaHost 的不同区域：改共享文件前重新读取、只做最小局部插入、不重写。**验证一律在工作区内，不在 /tmp 做隔离副本**；swift test 用 CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/clang-cache" TMPDIR="$PWD/.build/tmp"（目录已存在）--cache-path "$PWD/.build/cache" --disable-sandbox --disable-automatic-resolution --skip-update；磁盘只有约 3 GB，节省。Kotlin 只读，commit 2bdd3c58b，路径前缀 /Users/wujie/Work/legado-ios/app/src/main/java/io/legado/app/。Swift 语言模式 5；不加第三方依赖；不 commit；不联网。TDD 先红后绿；报告附命令与末尾 10 行、测试总数。汇报格式：中文 markdown ≤ 60 行。
Kotlin 规格：lib/mobi/*（34 个文件 1633 行：PDB 头、MOBI 头、EXTH、记录解压（PalmDoc LZ77、HUFF/CDIC）、KF8 / KF7 判定、NCX / guide 目录、HTML 分段、图片记录、编码 cp1252 / UTF-8）、model/localBook/MobiFile.kt（目录与正文抽取、封面）、model/localBook/PdfFile.kt（每 N 页一章或按书签、文本提取）、LocalBook.kt 的类型分派。已有：LocalBook/（TXT / EPUB、ZipReader、TextEncodingDetector）。
产出：
1. LegadoCore：LocalBook/Mobi/{PdbReader,MobiHeader,PalmDocDecoder,HuffCdicDecoder,MobiBook}.swift（按 Kotlin 逐文件移植，保持函数名可对照）、LocalBook/MobiFile.swift（目录 / 正文 / 封面）、LocalBook/PdfFile.swift（PDFKit；macOS 侧可编译，PDFKit 在 macOS 也可用）；LocalBook 分派接入。
2. App：LocalImport 的文件类型扩展（mobi / azw3 / pdf），无新页面。
3. 测试：用脚本自造最小 MOBI（PalmDoc 压缩的合成文本，含 EXTH 标题与两章 HTML）与最小 PDF（PDFKit 生成两页文本）做目录与正文断言；HUFF/CDIC 用 Kotlin 测试里的固定样本若有，没有则说明未覆盖。
</task>
