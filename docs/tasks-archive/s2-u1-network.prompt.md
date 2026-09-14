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
目标：阶段 2 单元 U1 —— 在 LegadoCore 建立网络层：HttpClient protocol、URLSession 生产实现、测试用回放实现、StrResponse 模型、响应字符集解码、Cookie 存储，并把已有的 UrlOptions 映射为真实请求。
工作目录：/Users/wujie/Work/legado-ios/.claude/worktrees/ios（可写：Packages/LegadoCore/Sources/LegadoCore/Network/（新目录）、Tests/LegadoCoreTests/ 新文件、docs/spec/network-compat.md（新）；不得改 Package.swift（另一任务在改）、AnalyzeRule/、JsEngine/、AnalyzeByJSoup/ 等既有目录与既有测试；不加第三方依赖；不 commit）
背景与入口（Kotlin 为规格，只读，commit cb664b84d）：
- /Users/wujie/Work/legado-ios/app/src/main/java/io/legado/app/help/http/HttpHelper.kt（okHttpClient 构建、超时、重定向、Cronet 开关）、help/http/StrResponse.kt、help/http/OkHttpUtils.kt（text() 的字符集判定：响应头 charset → HTML meta → 默认；GBK 等解码）、help/http/EncodingDetect.kt（若被用到）、help/http/CookieManager.kt 与 help/http/CookieStore.kt（按域名的 cookie 字符串合并、getCookie / setCookie / replaceCookie / removeCookie / getKey 语义）、model/analyzeRule/AnalyzeUrl.kt 的 getStrResponse / getResponse 段（:400-620 附近：method、headers、body 编码为表单或 JSON、charset、retry 循环、followRedirects、timeout 派生、serverID、webView 分支只需留桩）、model/analyzeRule/AnalyzeUrlNetworkOptions.kt。
- 已有 Swift：Sources/LegadoCore/AnalyzeUrl/UrlOptions.swift（选项解析与 timeout 派生已实现，直接复用其模型）。
- 计划文档 docs/1-阶段2数据与网络/PLAN.md §3：HttpClient protocol + URLSessionHttpClient + ReplayHttpClient；async/await；Cookie 存储用 actor；dnsIp / resolveIp / 代理 / Cronet 选项解析保留、执行忽略并写进 docs/spec/network-compat.md。
产出：
1. Network/HttpClient.swift：protocol（async 发送 HttpRequest 得 HttpResponse（status、headers、body Data、finalURL））、HttpRequest 模型（method、url、headers、body、timeout、followRedirects）。
2. Network/URLSessionHttpClient.swift：生产实现，按请求逐项配置（含 followRedirects 通过 delegate 控制、重定向后 finalURL、每请求超时）。
3. Network/ReplayHttpClient.swift：测试实现，按 URL + method 匹配预录响应，记录收到的请求供断言，未匹配抛错。
4. Network/StrResponse.swift + Network/ResponseDecoder.swift：按 Kotlin 顺序判定字符集并解码为字符串（GBK / GB2312 / GB18030 / Big5 用 CFStringConvertEncoding），保留原始 Data。
5. Network/CookieStore.swift：actor，语义对齐 Kotlin CookieStore（含 cookie 字符串的解析 / 合并 / 覆盖规则，key 为 host）。
6. Network/UrlRequestBuilder.swift：从 url + UrlOptions（+ 书源 header JSON、cookie）构造 HttpRequest：method、headers（含 User-Agent 默认值按 Kotlin AppConfig.userAgent 的默认字符串）、body 编码（表单 vs JSON 判定按 Kotlin）、charset 编码 GET 参数、retry 循环、超时派生。webView 分支返回明确的「未实现」错误。
7. 测试：每个组件 TDD 先红后绿；用 ReplayHttpClient 覆盖 GET / POST 表单 / POST JSON / GBK 响应 / meta charset / 重定向 / retry 次数 / 超时派生 / cookie 合并；不发任何真实网络请求。
8. docs/spec/network-compat.md（中文 ≤ 40 行）：不支持项与行为差异清单。
约束：Swift 6.0 工具链、语言模式 5、iOS 17 / macOS 14；不 commit。
完成标准：在 Packages/LegadoCore 下用 CLANG_MODULE_CACHE_PATH=\"$PWD/.build/clang-cache\" swift test --cache-path .build/cache --config-path .build/config --security-path .build/security --disable-sandbox 跑全量（并行任务半成品导致编译失败时用隔离副本验证并说明）；报告附命令与末尾 15 行原始输出、测试总数、public API 一览、字符集判定顺序的 Kotlin 行号依据、network-compat 清单。
汇报格式：中文 markdown ≤ 60 行。
</task>
