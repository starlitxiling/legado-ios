# JS 宿主已知兼容差异

对照版本为 Kotlin/Rhino `cb664b84d`；本文记录当前边界，不把差异当作兼容行为。

## Java 对象、语言语义与共享库

| 差异 | 最小示例与当前结果 | 影响 |
| --- | --- | --- |
| java 方法返回原生 JS 字符串和数组，不模拟 Java 对象 | `java.md5Encode('abc').length()` 抛 TypeError；应使用 `.length`。`java.getElements('tag.p').size()` 不可用，应使用 `.length` | 依赖 Java String/List 方法的旧书源需要适配；普通 JS 规则的数值最终输出仍按 Double 转换，模板才去掉整数小数部分 |
| 不执行 Rhino 的 let/const 归一化 | `{ let x=1; } x` 在 JSC 抛 ReferenceError；`{ const x=1; } x` 同样不可读 | Kotlin 的归一化器对满足条件的块外读取恢复可见性；依赖这类旧作用域行为的脚本会失败 |
| 默认不注入 CryptoJS | `typeof CryptoJS` 返回 `undefined`；`CryptoJS.MD5('abc')` 抛 ReferenceError | 依赖 CryptoJS 的书源不能直接执行；宿主可用 `libraryInitializer` 注入库，系统 AES/MD5 方法不等于 CryptoJS 全局对象 |

原文依据：`modules/rhino/src/main/java/com/script/rhino/RhinoContext.kt:143-258`、
`app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeRule.kt:914-922`。
归一化发生在解析之后；不能从 `let` 改成 `var` 推断同作用域重复声明一定被 Kotlin 接受。
本机未运行 Rhino；JSC 重复 `let x` 抛 SyntaxError，重复 `var x` 可执行，这仅是 JSC 实验。

## ② 网络宿主失败语义：已对齐，平台差异见下表

`JsEngine` 注入 `HttpClient`（默认 `URLSessionHttpClient`）、`CookieStore`、`CacheManager`、
`AnalyzeUrlExecutor.Source`、`ConcurrentRateLimiter` 和 `HostDownloadStore`。离线测试注入 `ReplayHttpClient`。
`java.get(key)` 保持规则变量读取；二或三个参数的 `get(url, headers, timeout?)` 才访问网络。

| 方法 | 成功与非 2xx | 请求异常或超时 | Kotlin 原文 |
| --- | --- | --- | --- |
| `ajax(urlOrArray, callTimeout?)` | 返回正文 String，包括非 2xx 正文；数组只取第一项。 | 返回错误堆栈字符串，脚本可继续。 | `JsExtensions.kt:176-195` |
| `connect(url, headerJSON?, callTimeout?)` | 返回以 `body()/url()/code()/headers()/header(name)/raw()` 方法为主的响应对象，保留实际状态码。 | 返回 body() 为错误文本、code() 为 200 的合成响应；不是 500。 | `JsExtensions.kt:240-277`；`http/StrResponse.kt:32-47` |
| `ajaxAll(urls, skipRateLimit?)` | 返回响应数组，保持输入顺序；非 2xx 仍是响应。 | 异常向外传播，取消同批未完成请求。 | `JsExtensions.kt:200-214`；`AnalyzeUrl.kt:454-470` |
| `ajaxTestAll(urls, timeout, skipRateLimit?)` | 返回响应数组。 | 普通请求失败转为带负数 callTime 的响应；取消向外传播。 | `JsExtensions.kt:219-234`；`AnalyzeUrl.kt:553-578` |
| `get/head(url, headers, timeout?)`、`post(url, body, headers, timeout?)` | 返回方法对象，支持 `body()/header(name)/headers()/cookies()/cookie(name)/statusCode()/url()`；禁用自动跳转，接受 3xx，HEAD 正文为空。 | 请求异常向外传播；不包装为错误正文。当前将小于 200 或大于等于 400 的状态转为 HTTP 错误。 | `JsExtensions.kt:575-657`；底层 Jsoup 默认状态处理本机未取得源码验证。 |
| `downloadFile(url)`、`downloadFile(hex, url)` | 返回存储句柄；前者下载原始字节，后者解析十六进制。HTTP 错误状态本身不阻止取得响应字节。 | 下载、解码和存储异常向外传播。 | `JsExtensions.kt:518-569`；`AnalyzeUrl.kt:594-617` |
| `cacheFile(url, saveTime?)` | 返回缓存文本，过期或句柄不存在时重新下载；saveTime 单位为秒。 | 下载、缓存和读取异常向外传播。 | `JsExtensions.kt:479-493` |

以上路径省略共同前缀 `app/src/main/java/io/legado/app/`。
`ajax/connect` 在捕获请求异常之前构造 AnalyzeUrl；URL 脚本求值异常仍然抛出。取消错误不转换成可继续执行的正文。
非 2xx 重试复用 U1 `UrlRequestBuilder`，遵循 `http/OkHttpUtils.kt:29-43`，不对传输异常额外重试。
`connect` 的 null 或无效 JSON 请求头回退到书源头；`get/head/post` 的无效 JSON、类型或 null 字段抛出参数错误。

`AnalyzeUrlExecutor` 顺序处理 `<js>/@js:`、`{{...}}`、分页选择、`,{...}`、URL `js`、请求和响应 `bodyJs`。
有 `type` 时返回原始字节的小写十六进制文本，并使用合成响应；raw 请求中的 HEAD 按 Kotlin `getResponseAwait` 走 GET。
XML 响应缺声明时补声明并跳过 bodyJs。处理后的正文与服务器原始字节分别保存于 `Response.body` 和 `Response.raw.body`。
Swift 使用 `AnalyzeUrlExecutor.Response` 承载可变换正文，因为 U1 `StrResponse` 只能从原始响应解码；JS 可见字段保持上述约定。
StrResponse 和 Connection.Response 的同名成员使用可调用包装对象，按已确认的 Rhino Java 对象方法优先边界提供调用入口；
同时支持 `String(r.body)`、`Number(r.code)`、`r.body.includes(...)`、`r.body.toUpperCase()` 和 `r.body.length` 等属性转换及字符串成员转发。
不保证属性的原生类型及严格相等语义：`typeof r.body` 为 function，使用 `r.code() === 200`，不能使用 `r.code === 200`。
`headers()` 和 `cookies()` 提供 `get/containsKey/keySet/size` 及属性读取；keySet 返回原生 JS 数组，保留先前的 Java 集合边界。
同名数据键与 Map 方法冲突时方法优先，数据键用 `get(key)` 读取。raw() 返回未修改的原始响应对象。
书源配置由调用方显式注入 `networkSource`，不依赖尚未接入的实体或数据库。限流 actor 按书源 key 共享固定时间窗口，
`concurrentRate` 接受单个毫秒间隔或“次数/毫秒”；批请求默认并行度为 32，可配置。

`cookie` 注入对象支持 `getCookie/getKey/setCookie/replaceCookie/removeCookie`，均委派 U1 actor；
书源为非 URL key 时使用该 key 查询手动 Cookie，临时头覆盖手动 Cookie，enabledCookieJar 的二阶段处理仍由 U1 完成。
`cache` 支持 `put/get/getInt/getLong/getDouble/getFloat/delete`，包括 `get(key, onlyDisk)`；
字符串写入文件、无过期值进入 50 MiB 内存 LRU；0 秒永久有效，截止毫秒及之后失效，数值转换失败返回 null。

| 仍有差异的项 | 当前边界 |
| --- | --- |
| WebView 与 UI | 只有启用 webView 才进入未实现分支；单独 webJs 在普通 HTTP 路径忽略。ajax/connect 按自身错误契约包装 WebView 错误。toast、浏览器和验证 UI 尚未实现。 |
| 文件系统 | `downloadFile` 默认只保存内存字节，返回路径形状的句柄，不保证操作系统文件存在；落盘须实现并注入 `HostDownloadStore`。`readFile` 仍为桩。 |
| 缓存后端 | 字符串使用文件替代 Kotlin 数据库；未提供 ByteArray 的 ACache API、QueryTTF 与其他内存对象接口。浮点转换使用 Swift 语法，不支持 JVM 十六进制浮点字面量等扩展。 |
| 网络后端 | serverID 保留供 U6 WebDAV 凭据选择，普通 HTTP 不使用；DNS、代理、TLS、重定向和多值头边界沿用 `network-compat.md`。未复制 Jsoup 的完整 Response/URL/Headers Java 类型及默认 User-Agent、大小上限等内部行为。 |
| 文本探测 | 沿用 U1 ResponseDecoder；未实现 Kotlin ICU 统计字符集探测，因此无编码标记的非 UTF-8 文本缓存可能不同。 |
| JS 与取消 | URL 脚本使用现有 JsEngine 上下文隔离策略；不提供 Rhino 全局共享作用域。同步桥接在 UnsafeCurrentTask 的同步作用域内每 10 ms 检查外层取消，取消所保存的内部 Task；内部 withTaskCancellationHandler 唤醒等待，结果只完成一次，Swift 调用方收到 CancellationError。网络请求和限流等待均已验证真正外层 Task 取消；这不提供任意纯 JS 无限循环的抢占。大量同步求值仍应放在独立线程，不占满 Swift 协作线程池。 |
| 错误文本 | 返回 Swift 错误和 Swift 调用栈，不逐字模拟 JVM 类名、堆栈和平台超时分类；未运行 Android/Rhino 对照。 |

既有网络及 cache 桩断言已迁移为当前契约，并注入离线依赖；全量验证不通过默认客户端访问真实网络。
