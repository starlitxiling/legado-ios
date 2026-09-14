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
目标：独立复审 LegadoCore 单元 4（SwiftSoup 实现的 AnalyzeByJSoup：Default 私有语法 + CSS 模式 + 索引 + 合并）是否忠实对齐 Kotlin 与规格 §5 / §6 / §11，并找出 SwiftSoup 与 jsoup 1.23.2 的语义差异风险。
工作目录：/Users/wujie/Work/legado-ios/.claude/worktrees/ios（分支 ios）
背景与入口：新文件（未跟踪）Packages/LegadoCore/Sources/LegadoCore/AnalyzeByJSoup/{AnalyzeByJSoup,JSoupIndex}.swift 及同目录其他文件、Tests/LegadoCoreTests/AnalyzeByJSoupTests.swift；Package.swift 已升 swift-tools-version 6.0（语言模式 5）并 exact 钉 SwiftSoup 2.13.9（源码在 .build/checkouts/SwiftSoup，可读）；ConformanceRunner.swift 新增 jsoup 分派。规格 docs/spec/rule-engine.md §5、§6、§11。Kotlin 只读：/Users/wujie/Work/legado-ios/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt（519 行）、SourceHtmlParser.kt（commit 2bdd3c58b）。实现者报告 76 测试全绿、71 条用例 68 passed / 3 skipped（JS），并说 SwiftSoup 对 XML Item 与 HTML div 的序列化带换行、但未能核对 jsoup。
审查角度：① 选择器首词 class / tag / id / text / children 与 jsoup 调用（getElementsByClass vs select 等）逐条对照；② 旧式索引（独立索引、负数）与新式索引（区间、步长、零步长取 len、! 排除、顺序去重、反向）对照 AnalyzeByJSoup.kt:275-501；③ 末段关键字 text / textNodes / ownText / html（删 script/style 且影响后续规则）/ all / 属性名 的语义，以及 outerHtml / html 序列化与 jsoup 的 pretty-print 差异（jsoup 1.23.2 默认 outputSettings prettyPrint=true；请读 SwiftSoup 源码 .build/checkouts/SwiftSoup/Sources/ 中 OutputSettings 与 Element.outerHtml 的实现来判断换行 / 缩进是否一致，这是最高风险点）；④ 字符串入口与元素入口的 && / || / %% 差异（%% 元素入口空首项返回 []）；⑤ 空规则返回 [] 与 @CSS: 剥离后为空返回 [element.data()]；⑥ SourceHtmlParser 对 <a/> 自闭合的兼容是否复刻；⑦ 「协议入口收到字符串时重新解析」会不会让 html 关键字删 script/style 的副作用在同一文档的后续规则中丢失（Kotlin 是在同一 Document 上操作）；⑧ 测试是否迁就实现（实现者提到把「紧凑排版假设」改成了「结构断言」，请核对是否绕开了序列化差异）。
约束：只读，不修改文件，不 commit，不编译。
完成标准：finding 列表（文件绝对路径:行号、置信 0-100、具体输入下 Swift 与 Kotlin/jsoup 行为差异、建议），< 60 不列；序列化差异若确认，给出最小复现输入与两端输出。没有就写 clean 并列出对照过的项。
汇报格式：中文 markdown ≤ 55 行。
</task>
