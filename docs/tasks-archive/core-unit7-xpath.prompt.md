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
目标：阶段 1 单元 7 —— 实现 XPath 模式（@XPath: 与 / 开头）作为 SelectorEngine 的 xpath 实现，对齐 Kotlin 用的 JsoupXpath 2.5.3 语义，接通 xpath 一致性用例。
工作目录：/Users/wujie/Work/legado-ios/.claude/worktrees/ios（可写：Packages/LegadoCore/Package.swift（加依赖）、Sources/LegadoCore/AnalyzeByXPath/（新目录）、Sources/LegadoCore/Conformance/ConformanceRunner.swift（加 xpath 分派与注入，编辑前重新读取、局部修改）、Tests/LegadoCoreTests/ 新文件；AnalyzeRule/ 只允许最小接入改动并逐处列出；不得改 RuleAnalyzer.swift、UrlOptions.swift、AnalyzeByJSoup/、JsEngine/、AnalyzeByJSonPath/ 与既有测试；不 commit）
背景与入口：
- 规格 docs/spec/rule-engine.md §4 XPath 模式、§6（AnalyzeRule 层已做递归合并）、§11「未确定 U7：JsoupXpath 扩展函数集与 asString() 格式」。Kotlin 只读：/Users/wujie/Work/legado-ios/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByXPath.kt（155 行：文档来源既可能是 jsoup Element 也可能是字符串重新解析；结果 asString / 元素列表的转换），commit 2bdd3c58b。JsoupXpath 在 jsoup DOM 上执行 XPath 1.0 并扩展了若干函数（如 text() 的特殊语义、num()、allText()、outerHtml()、html() 等），请从 Kotlin 调用与你对该库的把握列出需要支持的扩展，标注哪些未核实。
- 依赖：iOS 侧 XPath 只能用 libxml2。优先方案 Kanna（GitHub tid-kijyun/Kanna，exact 钉最新稳定版），它在 libxml2 的 HTML 解析树上跑 XPath 1.0；注意 libxml2 的 HTML 解析树与 jsoup 的 HTML5 解析树可能不同（标签补全、实体、大小写），用例失败时不要改期望值，列入「库差异」清单并标 failed。SwiftPM 解析依赖需要网络，沙箱不可用时把原始错误贴进报告并停在那里，主会话会 resolve 后让你续跑。
- 已有代码：SelectorEngine protocol、AnalyzeRule 的 XPath 模式分派、AnalyzeByJSoup 的 DOM 缓存（XPath 需要在同一文档上执行时，说明你如何在 SwiftSoup DOM 与 libxml2 之间桥接：最简单是把当前 Element 的 outerHtml 交给 libxml2 重新解析，报告里写明此选择及其副作用风险）。
- 用例：Tests/Conformance/fixtures/synthetic/synthetic-xpath.json（4 条，当前 unsupported）；本单元应跑通，并用 TDD 覆盖：绝对 / 相对路径、谓词、属性取值 @attr、text() / 多文本节点、contains / starts-with、位置 [last()] [1]、// 递归、union |、对元素列表的结果（后续 @ 链）。
产出：AnalyzeByXPath/AnalyzeByXPath.swift（及桥接文件）；Tests/LegadoCoreTests/AnalyzeByXPathTests.swift（先红后绿，注明规格 / Kotlin 行号）；ConformanceRunner 分派；Package.swift 依赖。
约束：Swift 6.0 工具链、语言模式 5、iOS 17 / macOS 14；不 commit。
完成标准：在 Packages/LegadoCore 下用 CLANG_MODULE_CACHE_PATH=\"$PWD/.build/clang-cache\" swift test --cache-path .build/cache --config-path .build/config --security-path .build/security --disable-sandbox 跑全量；报告附命令与末尾 20 行原始输出、测试总数、xpath 用例明细、JsoupXpath 扩展函数支持清单、库差异清单、桥接方案说明。
汇报格式：中文 markdown ≤ 65 行。
</task>
