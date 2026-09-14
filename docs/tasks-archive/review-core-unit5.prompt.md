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
目标：独立复审 LegadoCore 单元 5（JavaScriptCore JS 引擎：<js> / @js: / {{ }} 求值、注入变量、java 宿主一级离线子集）是否忠实对齐 Kotlin 与规格，并评估与 Rhino 语义的兼容风险。
工作目录：/Users/wujie/Work/legado-ios/.claude/worktrees/ios（分支 ios）
背景与入口：新文件（未跟踪）Packages/LegadoCore/Sources/LegadoCore/JsEngine/{JsEngine,JavaHost}.swift、Tests/LegadoCoreTests/JsEngineTests.swift；AnalyzeRule.swift 新增 scriptBindings（:45 附近）；ConformanceRunner.swift 新增 JS 分派（:43、:128、:274）。规格 docs/spec/rule-engine.md §2（JS 切段、{{ }} 模板参数）、§4（JS / WebJs 模式）、§8、§9（注入变量表与 6 个调用点的 result 含义）、§11。Kotlin 只读：/Users/wujie/Work/legado-ios/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeRule.kt（evalJS、buildScriptBindings :897-911、getString 对 JS 结果的处理）、AnalyzeUrl.kt:396-411、/Users/wujie/Work/legado-ios/app/src/main/java/io/legado/app/help/JsExtensions.kt、JsEncodeUtils.kt、/Users/wujie/Work/legado-ios/modules/rhino/src/main/java/com/script/rhino/（RhinoContext.kt、RhinoScriptEngine.kt、RhinoWrapFactory.kt），commit cb664b84d。实现者报告：一级方法实现了 put / getString / get / timeFormat / log / md5Encode / base64Decode / getElements / setContent / toNumChapter / aesBase64DecodeToString / encodeURI / getElement，其余留桩抛未实现；java.* 返回原生 JS 值不模拟 Java 对象；不改写 let/const；不注入 CryptoJS；page 转 Int32。
审查角度：① JS 结果到规则结果的类型转换（Kotlin 对 evalJS 返回值：null / undefined / 数组 / List / 数字 / 对象 的 toString 规则，含 Double 的 %.0f 与整数化）；② 注入变量的名称、类型、存在条件是否与 §9 及 Kotlin 一致（result 在 6 个调用点的含义、src、baseUrl、book / chapter 骨架、page / key / speakText）；③ {{ }} 模板参数拆分与 URL 内插求值顺序（@put 剥离在前、{{page}} 为 JS 变量引用）；④ 每个已实现 java 方法的签名与语义逐个对照 Kotlin（timeFormat 的格式串、md5Encode 大小写与编码、base64Decode 默认 flags、aesBase64DecodeToString 的参数顺序 / 模式 / padding / 返回编码、encodeURI 的字符集、toNumChapter）；⑤ 未实现桩是抛异常还是返回 undefined，与 Kotlin 在同样情形（如网络失败）下的行为差异是否会改变规则结果；⑥ JSContext 生命周期与线程安全（每次求值新建 vs 复用、异常是否泄漏）；⑦ 测试是否迁就实现。
约束：只读，不修改文件，不 commit，不编译。
完成标准：finding 列表（文件绝对路径:行号、置信 0-100、具体输入下 Swift 与 Kotlin/Rhino 行为差异、建议），< 60 不列；没有就写 clean 并列出对照过的项。
汇报格式：中文 markdown ≤ 55 行。
</task>
