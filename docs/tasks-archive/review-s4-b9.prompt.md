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
目标：只读复审阶段 4 单元 B9「阅读器进阶」的未提交改动（git diff HEAD 与未跟踪文件中属于 B9 的部分），对照 Kotlin（commit 2bdd3c58b，只读，前缀 /Users/wujie/Work/legado-ios/app/src/main/java/io/legado/app/）找出与 Android 行为不一致、逻辑错误、并发 / 生命周期缺陷、测试固化错误期望的问题。工作目录 /Users/wujie/Work/legado-ios/.claude/worktrees/ios。
B9 范围（其他未提交改动属于并行的 B8 / B10，忽略）：Packages/LegadoCore/Sources/LegadoCore/Reader/（ReadBookConfig、ReaderSharedConfig、BookHighlight、ReaderMigration、ReaderReviewEvaluator）、Content/ReaderTitleStyle.swift 与 Content/Paginator.swift 的局部改动、App/Sources/Features/Reader/{PageAnimation,FontPicker,Bookmark*,Highlight*,AutoRead*}、ReaderSettings.swift / ReaderView.swift 的局部改动、tools/appcore-check/Tests/ReaderAdvancedCheckTests、LegadoCoreTests/ReaderReviewTests。
Kotlin 对照点：help/config/ReadBookConfig.kt（Config 字段与默认值、共享项 shareLayout、主题导入导出）、ui/book/read/page/ReadView.kt 与 page/delegate/*（九宫格触摸区域、动画切换、滚动模式边界）、ui/book/read/page/provider/ChapterProvider.kt（标题 titleMode / titleSize / titleTopSpacing / titleBottomSpacing 的排版换算：titleSize 是相对正文字号的偏移、间距单位 dp 与 lineSpacing 关系）、ReadBookActivity 的 autoPage（autoReadSpeed 语义：秒/页 还是 行/秒，回源）、data/entities/{Bookmark,BookHighlight}.kt、data/entities/rule/ReviewRule.kt、help/book/BookHelp.kt hasContent。
方法：先 git status / git diff 定位 B9 文件；每个 finding 给 Swift 文件绝对路径:行号 与 Kotlin 文件:行号 依据；标 P1/P2/P3 与置信度；只报告确有依据的问题，不报告风格。不修改任何文件、不运行 xcodegen / xcodebuild、不在 /tmp 做副本；可以跑 swift test（命令：CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/clang-cache" TMPDIR="$PWD/.build/tmp" swift test --package-path <pkg> --cache-path "$PWD/.build/cache" --disable-sandbox --disable-automatic-resolution --skip-update --filter <名>），但读代码为主。
交付：中文 markdown ≤ 50 行；无问题则明确写 clean 并说明抽查了哪些对照点。
</task>
