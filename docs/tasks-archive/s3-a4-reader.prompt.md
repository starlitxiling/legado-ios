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
目标：阶段 3 单元 A4 —— 阅读器：CoreText 分页、翻页、章节切换与预取、进度持久化、字号 / 行距 / 主题最小配置、替换规则生效、章节缓存。
工作目录：/Users/wujie/Work/legado-ios/.claude/worktrees/ios。工程骨架见 App/（project.yml 为真源，XcodeGen 按目录收集源文件，**不要运行 xcodegen、不要改 project.yml 与 Legado.xcodeproj**，新文件放进 App/Sources/Features/<功能>/ 即可）。已有：App/Sources/App/{LegadoApp,AppContainer,RootTabView,DatabaseLifecycleCoordinator}.swift、Features/Bookshelf、Shared/{Theme,EmptyStateView}；并行任务正在写 Features/Sources、ReplaceRules（A2）与 Features/Search、BookDetail、Toc（A3），不要碰这些目录，接口对接用 protocol 或导航值约定并在报告写明。LegadoCore（Packages/LegadoCore）提供 Entities、Storage Repositories（书架 / 章节 / 阅读进度 / 书签 / 替换规则）、WebBook（BookContent 取正文）、Content/ContentProcessor、Backup/WebDavBackupSource、WebDAV/WebDavClient、Network/BoundedURLSessionHttpClient、Import。ViewModel 与纯逻辑放在不 import UIKit / SwiftUI 的文件里，用 @Observable；单测走 tools/appcore-check（已有 SwiftPM 包，通过软链接引用 App 下不含 UI 的文件，追加自己的目标即可）。本机无 iOS 平台组件，你不能跑 xcodebuild。Swift 语言模式 5；不加第三方依赖；不 commit；不联网。
Kotlin 参考（只读，commit cb664b84d，只看排版参数与进度语义，不移植 View）：/Users/wujie/Work/legado-ios/app/src/main/java/io/legado/app/help/config/ReadBookConfig.kt（字号、行距、段距、缩进、边距、主题字段与默认值）、model/ReadBook.kt（durChapterIndex / durChapterPos 的更新与保存时机、上下章预取）、ui/book/read/page/provider/ChapterProvider.kt（标题与正文的分段、段首缩进、页边界计算思路）。
产出：
1. App/Sources/Features/Reader/Paginator.swift（无 UI 依赖：输入章节标题 + 正文段落、页面尺寸、排版参数，用 CoreText CTFramesetter 切页，输出每页的字符范围与属性字符串；支持从字符偏移定位页码、页内首字偏移，供进度保存 / 恢复）；ReaderSettings.swift（字号、行距倍数、段距、缩进、边距、主题（日 / 夜 / 护眼），默认值对齐 ReadBookConfig，用 UserDefaults 持久化，key 名对齐 Android 字段名）。
2. ReaderViewModel.swift（无 UI：加载书与目录、按章节取正文（先查 ChapterRepository 的缓存字段或本地缓存目录，无则走 BookContent 抓取并缓存）、应用 ContentProcessor 替换规则、分页、上下页 / 上下章、预取下一章、进度持久化（durChapterIndex / durChapterPos / durChapterTitle / durChapterTime）到书架、书签列表读取）。
3. ReaderView.swift（SwiftUI：全屏、TabView 分页或自定义横向翻页、点击中间呼出工具栏：目录 / 设置 / 上一章 / 下一章 / 进度条；设置面板改字号行距主题即时重排；系统返回时保存进度）。与 Toc（A3）的对接：接受「书 + 章节 index」导航值进入。
4. 单测（appcore-check 新目标）：分页器在固定尺寸、固定字体下对给定文本的页数与页边界稳定；进度偏移 ↔ 页码互转；ReaderViewModel 用内存库 + ReplayHttpClient 走「取正文 → 替换 → 分页 → 翻到下一章 → 进度落库」。
完成标准：appcore-check 相关目标 swift test 通过；LegadoCore 全量 swift test 仍通过；报告附命令与末尾 10 行、文件清单、对接约定、留桩项（图片正文、TTS 等）。
汇报格式：中文 markdown ≤ 55 行。
</task>
