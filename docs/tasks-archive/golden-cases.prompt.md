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
目标：把 Legado Android 版现有的规则引擎单元测试转换成语言无关的 JSON 黄金用例，供 iOS 端 Swift 实现做一致性测试；期望值只能来自测试里已有的断言。
工作目录：/Users/wujie/Work/legado-ios/.claude/worktrees/ios（只能写入这里的 Tests/Conformance/fixtures/golden/ 目录，不存在就创建）
背景与入口：Kotlin 测试在主 checkout（只读，绝对路径）/Users/wujie/Work/legado-ios/app/src/test/java/io/legado/app/model/analyzeRule/（已知含 AnalyzeByJSoupDomTest、AnalyzeUrlNetworkOptionsTest 等 6 个文件），另用 `grep -rl "AnalyzeRule\|RuleAnalyzer\|AnalyzeBy\|ReplaceRule\|HtmlFormatter\|TxtTocRule" /Users/wujie/Work/legado-ios/app/src/test` 找其他相关测试；测试引用的 resource 文件也可读。规则引擎模式：CSS（jsoup）、私有 @ 语法、XPath、JSONPath、正则、JS、URL 选项解析。iOS 端测试运行器待建，本任务只产出数据文件与 schema，不写 Swift。
产出：
1. Tests/Conformance/fixtures/golden/README.md：定义用例 JSON schema，字段 id（golden-<测试类>-<序号>）、source（Kotlin 测试文件相对路径、方法名、行号、commit cb664b84d）、kind（jsoup-default / jsoup-css / xpath / jsonpath / regex / js / url-options / replace / format 之一，按实际出现的加）、input（document 原文、documentType: html/json/text、rule、可选 baseUrl 与 variables）、expect（type: string / stringList / error；value）、notes；凡测试依赖 Android 类（TextUtils、Base64、Uri、Context）或网络、数据库的用例标 requiresAndroid: true 并在 notes 写原因。README 里再放「未转换」表与「待人工确认」表。
2. 每个 Kotlin 测试类一个 JSON 文件（数组），每个 @Test 方法内的每条独立断言一条用例，期望值原样搬运（含空白、换行、转义）；注意 assertEquals(expected, actual) 的参数顺序。
约束：期望值只能来自断言，不得推导或补充；拿不准断言语义的用例放「待人工确认」表，不硬转。JSON 用 2 空格缩进、UTF-8、键按 schema 顺序。不改主 checkout，不 commit。大测试文件分段读。
完成标准：用 python3 校验目录内全部 JSON 可解析，并统计用例总数、按 kind 分布、requiresAndroid 数量；抽 3 条用例回 Kotlin 源码逐字核对期望值。
汇报格式：中文 markdown ≤ 50 行：生成文件清单；统计数字；校验命令与输出；未转换与待人工确认清单；对 iOS 实现有用的测试意图（如某测试专门防的回归）。
</task>
