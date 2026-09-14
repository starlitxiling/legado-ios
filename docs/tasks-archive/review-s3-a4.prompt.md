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
目标：独立复审阶段 3 单元 A4（阅读器：CoreText 分页器、阅读设置、章节缓存、ReaderViewModel、ReaderView）。
工作目录：/Users/wujie/Work/legado-ios/.claude/worktrees/ios（分支 ios）
背景与入口：新文件（未跟踪）App/Sources/Features/Reader/{Paginator,ReaderSettings,ReaderChapterCache,ReaderViewModel,ReaderView}.swift、tools/appcore-check 的 ReaderCheck 目标与 ReaderTests。依赖 LegadoCore 的 WebBook/BookContent、Content/ContentProcessor、Storage Repositories（书架进度 / 章节 / 书签）。Kotlin 参考（只读，commit 2bdd3c58b）：/Users/wujie/Work/legado-ios/app/src/main/java/io/legado/app/help/config/ReadBookConfig.kt（默认字号 / 行距 / 段距 / 缩进 / 边距 / 主题字段名与默认值）、model/ReadBook.kt（durChapterPos 的语义是字符偏移；保存时机；上下章预取；loadContent 的缓存优先）、help/book/BookHelp.kt（章节缓存文件命名与目录）、ui/book/read/page/provider/ChapterProvider.kt（标题独立段、段首缩进、段距、页边界）。
审查角度：① Paginator：CTFramesetter 的 frame 尺寸与 insets、行距倍数的实现方式（paragraphStyle lineSpacing vs 行高倍数）、段距、缩进用全角空格还是 firstLineHeadIndent（Android 用字符缩进）、标题段样式、页末字符范围是否与下一页首字连续无重叠无遗漏、超长单段跨页、空章节 / 只有标题；② 偏移 ↔ 页码互转在重排（改字号）后的稳定性；③ ReaderViewModel：进度保存字段（durChapterIndex / durChapterPos / durChapterTitle / durChapterTime）与 Kotlin 一致、保存节流与退出保存、预取下一章的取消与内存占用、章节缓存目录与命名、替换规则在缓存前还是缓存后应用（Kotlin 缓存原文、显示时替换）、失败时进度不回退；④ ReaderView：手势与 TabView 的冲突、工具栏状态、设置即时重排时的当前位置保持、主题颜色；⑤ 线程：分页在后台还是主线程、@Observable 更新；⑥ 测试是否迁就实现。
约束：只读，不修改文件，不 commit，不编译。
完成标准：finding 列表（文件绝对路径:行号、置信 0-100、问题与建议），< 60 不列；没有就写 clean 并列出对照项。
汇报格式：中文 markdown ≤ 50 行。
</task>
