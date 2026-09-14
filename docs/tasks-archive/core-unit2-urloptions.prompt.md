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
目标：阶段 1 单元 2 —— 在 LegadoCore 里实现 AnalyzeUrl 的「URL 选项解析与派生」纯逻辑部分，并建立一致性用例运行器，让 swift test 直接消费 golden 与 synthetic 里 kind 为 url-options 的用例。
工作目录：/Users/wujie/Work/legado-ios/.claude/worktrees/ios（只能写入 Packages/LegadoCore/ 下的新文件与 Tests/LegadoCoreTests/；**不要改 RuleAnalyzer.swift 与 RuleAnalyzerTests.swift**（另一任务正在复审它们）；可以改 Package.swift 但本单元不需要新依赖；不 commit）
背景与入口：
- 规格 docs/spec/rule-engine.md §10「AnalyzeUrl 的 URL 语法与选项」（含 17 个选项键的类型、默认值、语义，宽松 JSON 解析，timeout 派生 max(60000, min(2147483647, 2×timeout))，webView 真值判断（\"0\" 为真、\"false\" 为假）等）。规格有歧义时允许读 Kotlin：/Users/wujie/Work/legado-ios/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeUrl.kt（UrlOption 类与 :248-315 的选项解析）、AnalyzeUrlNetworkOptions.kt（commit 2bdd3c58b），Kotlin 为准并在报告里指出规格行号。
- 用例：Tests/Conformance/fixtures/golden/AnalyzeUrlNetworkOptionsTest.json（7 条）与 Tests/Conformance/fixtures/synthetic/synthetic-url.json（18 条）；schema 见两个目录的 README.md。先读用例再设计 API，API 要能直接满足用例里的 input / expect 形态。
- 已有：Sources/LegadoCore/Conformance/ConformanceCase.swift（Codable 模型）。本单元只做选项解析与派生，不发网络请求、不执行 JS（含 <js> 段与 {{}} 的用例若无法离线求值，运行器标 skipped 并计数，不得假绿）。
产出：
1. Sources/LegadoCore/AnalyzeUrl/UrlOptions.swift：按规格 §10 定义选项模型、从「url,{json}」拆分与解析（严格 JSON 失败后宽松解析，与 Kotlin 一致）、各字段的类型容错（字符串 / 数字 / 布尔互转规则按规格）、timeout 派生、webView 真值、headers / body 处理。
2. Sources/LegadoCore/Conformance/ConformanceRunner.swift：加载 golden 与 synthetic 目录全部 JSON，按 kind 分派；本单元实现 url-options 分派，其余 kind 记为 unsupported 并在测试输出里打印各 kind 的 supported / skipped / passed / failed 计数。
3. Tests/LegadoCoreTests/UrlOptionsTests.swift（TDD：先写会失败的单元测试，来源规格 §10 示例 + 边界）与 Tests/LegadoCoreTests/ConformanceUrlOptionsTests.swift（跑 25 条 url-options 用例，逐条断言，失败要打印用例 id）。
约束：Swift 5.10 工具链、iOS 17 / macOS 14；不加依赖；不写 UI；贴合单元 1 的代码风格；不 commit。
完成标准：在 Packages/LegadoCore 下用 CLANG_MODULE_CACHE_PATH=\"$PWD/.build/clang-cache\" swift test --cache-path .build/cache --config-path .build/config --security-path .build/security --disable-sandbox 跑全量；报告附命令与末尾 20 行原始输出、测试总数、25 条用例的 passed / skipped 明细（skipped 的要给原因）；若某条 synthetic 用例的期望值你按 Kotlin 推导认为是错的，不要改用例，在报告里单列并附推导。
汇报格式：中文 markdown ≤ 60 行：文件清单；API 一览；红→绿过程；测试与用例统计；原始输出；规格歧义与疑似错误用例。
</task>
