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
目标：独立复审 LegadoCore 单元 7（Kanna / libxml2 实现的 XPath 模式）是否对齐 Kotlin 的 JsoupXpath 2.5.3 用法与规格 §4，并评估 libxml2 与 jsoup 解析树差异带来的风险。
工作目录：/Users/wujie/Work/legado-ios/.claude/worktrees/ios（分支 ios）
背景与入口：新文件（未跟踪）Packages/LegadoCore/Sources/LegadoCore/AnalyzeByXPath/{AnalyzeByXPath,XPathNode}.swift、Tests/LegadoCoreTests/AnalyzeByXPathTests.swift；Package.swift 新增 Kanna 6.1.0（源码 .build/checkouts/Kanna 可读）；ConformanceRunner.swift 的 xpath 分派；AnalyzeRule.swift 新增 xpathContent(for:)（:167）。Kotlin 只读：/Users/wujie/Work/legado-ios/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByXPath.kt（155 行）、AnalyzeRule.kt 的 XPath 模式分派，commit 2bdd3c58b。实现者报告：桥接用 SwiftSoup Element 的 outerHtml 交给 libxml2 重新解析；text() 用 libxml2 文本节点语义；num() / allText() / outerHtml() / html() 显式报错；4 条 xpath 用例全过；HTML5 标签补全、实体、大小写、序列化差异未对照。
审查角度：① Kotlin AnalyzeByXPath 的入口类型（Element / Elements / String / JXNode）与结果转换（getStringList 对 JXNode 的 asString / 元素 outerHtml / 属性值 / 文本；getElements 返回 JXNode 列表再交给后续 @ 链）逐条对照 Swift；② JsoupXpath 与标准 XPath 1.0 的差异点（例如 text() 在 JsoupXpath 里返回元素自身文本而非文本节点；@attr 取值；contains；position；扩展函数）——你有网络就查 JsoupXpath 2.5.3 源码或 README（给 URL），没有就按把握标置信；③ libxml2 HTML 解析与 jsoup 的树差异会影响哪些常见书源规则（如 //div[@class='x']/a/@href 在缺少 html/body 包裹的片段、自闭合、实体、大小写标签）；给最小复现；④ 桥接副作用：outerHtml 重新解析后节点身份与祖先关系丢失，会不会让「XPath 结果元素上继续 @ 链」的结果与 Kotlin 不同；⑤ ConformanceRunner 与 AnalyzeRule 接入的最小改动是否破坏其他模式；⑥ 测试是否迁就实现。
约束：只读，不修改文件，不 commit，不编译。
完成标准：finding 列表（文件绝对路径:行号、置信 0-100、具体输入下 Swift 与 Kotlin 行为差异、建议），< 60 不列；没有就写 clean 并列出对照过的项。
汇报格式：中文 markdown ≤ 50 行。
</task>
