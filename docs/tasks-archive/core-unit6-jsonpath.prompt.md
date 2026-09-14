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
目标：阶段 1 单元 6 —— 实现 JSONPath 模式（@Json: / $. / $[ 前缀）作为 SelectorEngine 的 json 实现，对齐 Kotlin 用的 jayway json-path 3.0.0 默认配置语义，接通 jsonpath 一致性用例。
工作目录：/Users/wujie/Work/legado-ios/.claude/worktrees/ios（可写：Packages/LegadoCore/Sources/LegadoCore/AnalyzeByJSonPath/（新目录）、Sources/LegadoCore/Conformance/ConformanceRunner.swift（加 jsonpath 分派与引擎注入，编辑前重新读取、局部修改）、Tests/LegadoCoreTests/ 新文件；AnalyzeRule/ 目录只允许接入所需的最小改动并逐处列出；不得改 RuleAnalyzer.swift、UrlOptions.swift、AnalyzeByJSoup/、JsEngine/ 与既有测试；不加第三方依赖（自行实现 JSONPath 子集）；不 commit）
背景与入口：
- 规格 docs/spec/rule-engine.md §4 JSONPath 模式、§6 合并（AnalyzeRule 层已做递归合并，本引擎只需单规则求值）、§11（AnalyzeByJSonPath 用 jayway 默认配置而非 SUPPRESS_EXCEPTIONS，靠 try/catch 吞异常，getObject 例外直接抛；「未确定 U1：无 $ 前缀路径是否自动补 $.」——请读 Kotlin 与 jayway 的实际行为后在报告里给结论）。Kotlin 只读：/Users/wujie/Work/legado-ios/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSonPath.kt（175 行）、AnalyzeRule.kt 里 Json 模式的分派与结果字符串化（对象 / 数组用 Gson 序列化的规则），commit 2bdd3c58b。
- jayway 语义要点（无网络，按你对 json-path 3.0 的把握实现，并在报告里逐项列出你实现了哪些、哪些未实现）：根 $，子节点 .name / ['name'] / [\"name\"]，通配 *，递归下降 ..，数组索引 / 负索引 / 切片 [start:end:step] / 联合 [0,1]，过滤器 [?(@.x == 1)] 支持 == != < <= > >= =~ in nin size empty && || 与嵌套括号，函数 length() / min() / max() / sum() / first() / last()；定值路径（definite path）返回单值、不定路径返回数组；数字 / 布尔 / null / 对象的字符串化按 Kotlin 出口。
- 已有代码：SelectorEngine protocol、AnalyzeRule 的 Json 模式分派、ConformanceRunner。
- 用例：Tests/Conformance/fixtures/synthetic/synthetic-jsonpath.json（5 条，当前 unsupported）；本单元应全部跑通，并额外用 TDD 覆盖上述语义要点（每类正常 + 边界）。
产出：AnalyzeByJSonPath/{JsonPathParser,JsonPathEvaluator,AnalyzeByJSonPath}.swift（按需拆分）；Tests/LegadoCoreTests/AnalyzeByJSonPathTests.swift（先红后绿，注明规格 / Kotlin 行号）；ConformanceRunner 分派。
约束：Swift 6.0 工具链、语言模式 5、iOS 17 / macOS 14；JSON 解析用 Foundation JSONSerialization 并保留键序无关性；不 commit。
完成标准：在 Packages/LegadoCore 下用 CLANG_MODULE_CACHE_PATH=\"$PWD/.build/clang-cache\" swift test --cache-path .build/cache --config-path .build/config --security-path .build/security --disable-sandbox 跑全量；报告附命令与末尾 20 行原始输出、测试总数、jsonpath 用例明细、已实现 / 未实现的 jayway 语义清单、U1 结论。
汇报格式：中文 markdown ≤ 60 行。
</task>
