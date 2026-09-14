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
目标：阶段 3 单元 A3 —— 搜索、书籍详情、目录三个界面。
工作目录：/Users/wujie/Work/legado-ios/.claude/worktrees/ios。工程骨架见 App/（project.yml 为真源，XcodeGen 按目录收集源文件，**你不要运行 xcodegen、不要改 project.yml 与 Legado.xcodeproj**，新文件放进 App/Sources/Features/<功能>/ 即可被收集；主会话统一重新生成）。已有：App/Sources/App/{LegadoApp,AppContainer,RootTabView}.swift（依赖容器提供 Repository、HttpClient、数据库；四个 Tab 占位）、Features/Bookshelf、Shared/{Theme,EmptyStateView}。LegadoCore（Packages/LegadoCore）提供 Entities、Import/SourceImporter、Storage Repositories、WebBook、AnalyzeUrlExecutor、Network/BoundedURLSessionHttpClient、Backup/WebDavBackupSource。ViewModel 用 @Observable，只依赖 LegadoCore 的 protocol / Repository，便于用内存库与 ReplayHttpClient 单测。本机没有 iOS 平台组件，你无法跑 xcodebuild：请把 ViewModel 与纯逻辑放在不 import UIKit / SwiftUI 的文件里，并额外在 Packages/LegadoCore 之外建一个仅 macOS 可编译的验证方式——最简单是把 ViewModel 文件也加入一个临时 SwiftPM 包 tools/appcore-check/（依赖 ../../Packages/LegadoCore，通过符号链接或 path 引用 App/Sources/Features/<功能>/ 下不含 UI 的文件）用 swift test 跑 ViewModel 单测；报告写明做法。Swift 语言模式 5；不加第三方依赖；不 commit；不联网。
产出：
1. App/Sources/Features/Search/：SearchViewModel（对全部启用书源并发搜索：TaskGroup、并发上限可配（默认 8）、每源超时、按 name+author 聚合同一本书的多个来源、精准搜索开关传给 WebBook、可取消、增量发布结果）、SearchView（搜索栏、结果列表显示书名 / 作者 / 来源数 / 最新章节、进度指示、取消）。
2. App/Sources/Features/BookDetail/：BookDetailViewModel（拉详情 BookInfo、切换来源、加入 / 移出书架落库、跳转目录 / 阅读）、BookDetailView（封面占位、简介、来源、按钮）。
3. App/Sources/Features/Toc/：TocViewModel（BookChapterList 拉目录并落库 ChapterRepository、倒序、定位当前章、下拉刷新）、TocView（列表、章节名 / VIP 标记、点击返回选中章节 index 给阅读器——阅读器由 A4 实现，这里先用回调 / 导航值）。
4. 单测：搜索聚合去重与取消、加入书架落库、目录落库与倒序；用内存库与 ReplayHttpClient + Tests/Conformance/fixtures/webbook 的自造站点。
完成标准：同 A2。
汇报格式：中文 markdown ≤ 50 行。
</task>
