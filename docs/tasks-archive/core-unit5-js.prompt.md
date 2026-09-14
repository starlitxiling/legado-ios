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
目标：阶段 1 单元 5 —— 用 JavaScriptCore 实现规则引擎的 JS 模式（<js>…</js>、@js:、{{ }} 内插）与注入变量，作为 SelectorEngine 的 js 实现；本单元只做「离线可求值」部分：脚本执行、result / baseUrl / src / book / chapter / cookie / cache 等注入对象的骨架、java 宿主对象的最小子集（字符串 / 编码 / 时间 / log 等一级方法中不依赖网络与文件的部分）；网络请求类方法留桩并抛「未实现」。
工作目录：/Users/wujie/Work/legado-ios/.claude/worktrees/ios（可写：Packages/LegadoCore/Sources/LegadoCore/JsEngine/（新目录）、Sources/LegadoCore/Conformance/ConformanceRunner.swift（加 js 分派与 JS 引擎注入，编辑前重新读取、局部修改）、Tests/LegadoCoreTests/ 新文件；AnalyzeRule/ 目录下只允许为接入 JS 引擎做最小必要改动并在报告里逐处列出；不得改 RuleAnalyzer.swift、UrlOptions.swift、AnalyzeByJSoup/ 与既有测试；不加第三方依赖（JavaScriptCore 是系统框架）；不 commit）
背景与入口：
- 规格 docs/spec/rule-engine.md：§2 JS 切段与 {{ }} 模板参数拆分、§4 JS / WebJs 模式求值、§8 变量作用域、§9 JS 注入变量清单（两个 evalJS 的绑定表与 6 个调用点的 result 含义）、§11 怪癖（let/const 改写发生在 rhino 模块；CryptoJS 全局注入在 SharedJsScope）。规格有歧义时允许读 Kotlin：/Users/wujie/Work/legado-ios/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeRule.kt（evalJS、buildScriptBindings :897-911）、/Users/wujie/Work/legado-ios/app/src/main/java/io/legado/app/help/JsExtensions.kt、JsEncodeUtils.kt、/Users/wujie/Work/legado-ios/modules/rhino/src/main/java/com/script/rhino/RhinoContext.kt:143（normalizeLegacySource）（commit cb664b84d），Kotlin 为准并指出规格行号。
- 宿主 API 优先级：docs/0-iOS适配规划/宿主API优先级.md 的一级 16 个方法清单；本单元实现其中不依赖网络 / 文件 / WebView 的方法，其余留桩，报告里列出实现与留桩清单。
- 已有代码：SelectorEngine protocol（Sources/LegadoCore/AnalyzeRule/SelectorEngine.swift）、AnalyzeRule 的 JS 模式分派与变量存储、ConformanceRunner。
- 用例：golden/JsTest.json（8 条，看 README 判断哪些可离线）、synthetic-template-001/002/004、synthetic-replace-007/008、synthetic-url-017/018（{{page}}）；这些当前为 skipped / unsupported，本单元应把能离线求值的跑通，仍不能的说明原因。
- 关键决策待实证（写进报告）：① Rhino 下 java.* 返回的是 Java 对象（.length() 可用），JSC 返回原生 JS 值——本单元按原生 JS 值实现，并在报告里记录这一兼容差异；② Kotlin 把 let/const 改写为 var 以兼容老 Rhino，JSC 原生支持 let/const，本单元不改写，但要用一个最小实验（同名 let 在同一作用域重复声明的脚本）证明两端差异并记录；③ CryptoJS 全局注入：本单元不注入，留接口。
产出：JsEngine/JsEngine.swift（JSContext 生命周期、绑定注入、异常转换）、JsEngine/JavaHost.swift（java 对象：已实现方法 + 桩）、ConformanceRunner 分派；Tests/LegadoCoreTests/JsEngineTests.swift（TDD 先红后绿，注明规格行号）。
约束：Swift 6.0 工具链、语言模式 5、iOS 17 / macOS 14；不 commit。
完成标准：在 Packages/LegadoCore 下用 CLANG_MODULE_CACHE_PATH=\"$PWD/.build/clang-cache\" swift test --cache-path .build/cache --config-path .build/config --security-path .build/security --disable-sandbox 跑全量；报告附命令与末尾 20 行原始输出、测试总数、原 skipped / unsupported 的 JS 相关用例现在的 passed / skipped 明细与原因、实现与留桩的 java 方法清单、三项兼容决策的实验结论。
汇报格式：中文 markdown ≤ 70 行。
</task>
