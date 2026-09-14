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
目标：阶段 2 单元 U2 —— 把 JavaHost 的网络类方法从桩变成真实实现，建立在 U1 网络层之上，并实现注入对象 cookie / cache 的真实行为；失败语义对齐 Kotlin。
工作目录：/Users/wujie/Work/legado-ios/.claude/worktrees/ios（可写：Packages/LegadoCore/Sources/LegadoCore/JsEngine/（现有 JavaHost.swift、JsEngine.swift 及新文件）、Sources/LegadoCore/Network/ 下**只允许新增**文件（如 CacheManager.swift），Tests/LegadoCoreTests/ 新文件，docs/spec/js-host-compat.md（更新第 ② 类差异的状态）；不得改 Package.swift、Network/ 既有文件、Entities/、Import/、Storage/（其他任务在返修）、AnalyzeRule/ 与既有测试；不 commit）
背景与入口（Kotlin 为规格，只读，commit cb664b84d）：
- /Users/wujie/Work/legado-ios/app/src/main/java/io/legado/app/help/JsExtensions.kt 网络段（ajax :187 附近、ajaxAll、connect、get / head / post、getCookie、downloadFile / cacheFile 的签名、返回类型 StrResponse / String、失败时返回错误信息字符串而不抛出的规则、并发与 rate limit 调用）、help/CacheManager.kt（put / get / getInt / getLong / getDouble / getFloat / delete、过期、内存 + 文件 + DB 三层里本单元先做内存 + 文件缓存）、help/http/CookieStore.kt 通过 cookie 注入对象暴露给 JS 的方法、model/analyzeRule/AnalyzeUrl.kt 的 getStrResponse / getResponse（U2 在 JS 里调用 AnalyzeUrl 走同一条请求路径，含 ,{...} 选项）。
- 已有 Swift：Network/（HttpClient、URLSessionHttpClient、ReplayHttpClient、StrResponse、ResponseDecoder、CookieStore actor、UrlRequestBuilder 含 enabledCookieJar 两阶段与 retry）；JsEngine/JavaHost.swift 里现有桩与已实现的离线方法；docs/spec/js-host-compat.md 第 ② 类记录的「桩异常不等价网络失败」。
- 宿主 API 优先级表 docs/0-iOS适配规划/宿主API优先级.md：一级 / 二级里的网络相关方法全部实现。
产出：
1. JsEngine/JavaHostNetwork.swift（或拆分）：ajax / ajaxAll / get / head / post / connect / getCookie / cacheFile / downloadFile（本单元只到内存字节，落盘留接口）等，签名（重载、参数类型 Map / String / Array）与返回值（StrResponse 的 JS 可见属性：body / url / code / headers / raw；String）逐个对照 Kotlin；HttpClient 经 JsEngine 的依赖注入传入，默认 URLSessionHttpClient。
2. Network/CacheManager.swift（新增）：actor，内存 + 文件缓存，API 与过期语义对齐 Kotlin；注入对象 cache 的 JS 方法（put / get / getInt / getLong / getDouble / getFloat / delete）。
3. cookie 注入对象：JS 可调 getCookie(url) / getKey(url, key) / setCookie / replaceCookie / removeCookie，走 CookieStore actor。
4. 失败语义：网络失败 / 超时 / 非 2xx 时 Kotlin 各方法的实际返回（多数返回 StrResponse 且 body 为错误信息，或返回错误字符串），逐方法核对并对齐；更新 js-host-compat.md 第 ② 类为「已对齐」并列出仍有差异的项。
5. 测试：TDD 先红后绿；全部用 ReplayHttpClient，覆盖成功 / 超时 / 非 2xx / 异常 / cookie 回写 / cache 过期 / ajaxAll 并发顺序；JS 层用例通过 JsEngine 执行 java.ajax 等脚本断言结果。
约束：Swift 6.1 工具链、语言模式 5；不联网；不 commit。
完成标准：同样命令跑全量 swift test（并行任务半成品导致编译失败时用隔离副本并说明）；报告附命令与末尾 15 行原始输出、测试总数、已实现 / 留桩方法清单、失败语义对照表。
汇报格式：中文 markdown ≤ 60 行。
</task>
