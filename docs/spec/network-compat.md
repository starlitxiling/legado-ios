# 网络兼容性（阶段 2 U1）

规格基线为 Kotlin `2bdd3c58b`；网络请求经 `HttpClient` 注入。

- `URLSessionHttpClient` 使用临时会话，关闭系统 Cookie 与缓存，每请求设置空闲超时及资源总超时。
- `timeout` 为毫秒，映射时换算为秒；总超时复用 `UrlOptions.callTimeout` 派生规则。
- URLSession 无法分别复刻 OkHttp 的连接、读、写超时；未实现连接超时固定 15 秒。
- delegate 阻止自动跳转，客户端逐跳发送以等待 Cookie actor；停止跟随保留响应体和当前 URL，最多跟随 20 次。
- 重定向链共享总超时预算；跨源跳转删除 Authorization 和临时 Cookie，按目标域名重新加载存储。
- retry 为额外请求次数，仅非 2xx、非 3xx 的 HTTP 响应重试，异常与取消直接抛出。
- 普通响应字符集顺序为响应头、head 内 HTML meta、UTF-8；显式传给解码器的 charset 优先于响应头。
- Kotlin `OkHttpUtils.kt:80-95` 先移除 UTF-8 BOM；显式编码优先，然后响应头，然后内容探测。
- Kotlin `EncodingDetect.kt:18-57` 先扫描 meta，再调用 ICU CharsetDetector，最后 UTF-8。
- 本实现未移植 ICU 无声明编码探测；无 header/meta 的非 UTF-8 内容须显式指定解码 charset。
- `UrlOptions.charset` 只编码请求参数，不作为普通响应解码回退值。
- GBK、GB18030、Big5 通过 CoreFoundation 编码转换；GB2312 使用兼容其字节的 GBK，接受范围较宽。
- UTF-8 无效字节以替换字符解码；其他编码无法解码时抛错，不复刻 JVM 的所有替换规则。
- Cookie 为内存 actor，使用 PSL 可注册域名键；通配、例外、默认规则均支持，纯后缀按 Kotlin 回退 host。
- PSL 静态 Swift 表来自本地 Mozilla 数据（2026-09-08），不保证与 Android 所带 PSL 快照逐条相同。
- 运行 `uv run --offline --no-project tools/psl/generate_psl.py` 从本地 dat 重新生成；生成文件保留源数据 SHA-256。
- enabledCookieJar 默认 false：准备请求时 `AnalyzeUrl.kt:765` 按存储值、临时头的顺序合并，临时值覆盖同名存储值。
- 开启 CookieJar 后，`HttpHelper.kt:84-98` 的网络拦截器移除内部标记，再调用 `CookieManager.loadRequest`；
  `CookieManager.kt:62/101-105` 按请求值、存储值的顺序合并，存储值最终覆盖同名临时值。响应随后回写，再处理下一跳。
  这两阶段顺序以 Kotlin `2bdd3c58b` 为准；关闭 CookieJar 时不执行第二次合并，也不回写响应 Cookie。
- Cookie 同名后值覆盖前值；空值忽略，字符串 null 保留；set 整体覆盖，replace 合并，remove 删除。
- 不提供 Cookie 数据库持久化、会话与持久 Cookie 分层、4096 字节随机淘汰；App WebView 同步见下文。
- 响应 Cookie 通过 Foundation 解析；未实现完整过期清理、路径作用域。
- headers 用字典存储，同名头不保留多值顺序，重复 Set-Cookie 受 Foundation 合并行为影响。
- header 名称按 HTTP 大小写不敏感处理；Kotlin 部分分支按 Content-Type 精确键查找。
- 默认 User-Agent 固定使用规格中的 Chrome/153.0.0.0；不读取 Android 偏好设置。
- User-Agent 为精确字符串 null 时删除；其他头的 null 字符串按 Kotlin 保留。
- `dnsIp` / `resolveIp` 保留在 UrlOptions，执行忽略；代理和 Cronet 没有执行支持。
- 代理 / Cronet 不属于现有 UrlOptions 模型字段，书源 header 中的代理信息不建立代理连接。
- `serverID` 是 WebDAV 凭据选择标识，**保留字段，U6 接入**，不是普通 HTTP 服务器转发配置。
  Kotlin `lib/webdav/WebDav.kt:48-50` 从 AnalyzeUrl 读取该值；`lib/webdav/Authorization.kt:25-30` 据此查询服务器配置中的用户名和密码。
- U2 普通 HTTP 不使用 serverID；启用 webView 后交给注入的 WebView 服务，单独 webJs 在普通 HTTP 路径忽略。
- 宿主 `get/head/post` 的 timeout 缺省为 30,000 ms，0 表示不设超时，负数抛参数错误（`JsExtensions.kt:579-657`）。
  显式 ajax/connect callTimeout 的 0 同样表示不设总超时，负数无效（`AnalyzeUrlNetworkOptions.kt:117-118`）。
  同步宿主将“不设超时”转换为 `TimeInterval.greatestFiniteMagnitude` 传给 U1，避免零总预算在 URLSession 客户端立即失败；
  URLSession 加离线 URLProtocol/ReplayHttpClient 的用例验证了该传递路径，不使用真实网络。
- URL 选项 `,{"timeout":...}` 与上述显式参数不同：只有 1 至 Int32.max 的整数有效，0 或负数视为未设置，回落 U1 默认 60,000 ms，
  依据 `AnalyzeUrlNetworkOptions.kt:12-22`、`AnalyzeUrl.kt:980-981`；不把该分支的 0 当作无限超时。
- `js` / `bodyJs`、type 的十六进制响应、XML 声明补写由上层后续接入，本层不执行。
- 不实现 Android 并发限速器、ZIP 自动解压或 isTest 错误码封装。

## WebView（阶段 4 B4）

- Kotlin 基线为 `2bdd3c58b`。`BackstageWebView.kt:348-360` 的 `sourceRegex` 实际在 `onLoadResource` 中返回匹配的资源 URL，响应正文即 URL 字符串；该版本没有通过 `shouldInterceptRequest` 返回资源正文。`overrideUrlRegex` 在 `:331-344` 拦截跳转并返回目标 URL，两者均为全串正则匹配。
- LegadoCore 仅定义请求、异步加载及用户交互协议；AppContainer 安装服务，引擎创建时取服务快照。默认调度上限为 2，FIFO 排队计入总超时，默认 60 秒，取消后先释放加载器再释放槽位。实现必须响应任务取消；不响应取消的自定义加载器不能获得硬超时保证。
- 仅前台允许运行。WKWebView 作为 key window 的零尺寸子视图，退到非活跃状态即取消，完成、失败及取消均拆除视图与消息处理器。同步 JavaScript 宿主和 `@webjs:` 在主线程明确报错，调用方必须在后台执行规则。
- AnalyzeUrl 的 GET 加载 URL；POST 先用原 HTTP 客户端获得 HTML，再以响应 URL 为基址加载。关闭重定向且返回 3xx 时直接返回 HTTP 响应。传入 header、Cookie、webJs、延时、sourceRegex；`webJs` 优先于 jsStr。
- `@webjs:` 加载原始 HTML，注入 JSON 文本形态的 `window.result`，执行当前规则，预算为 10 秒。既有 AnalyzeRule 继续负责字符串、JSON 列表和对象结果转换。未移植 Android WebJsExtensions 的页面内 `java/source/cache` 桥；依赖这些页面桥的规则尚不兼容。
- `java.webView`、`webViewGetSource`、`webViewGetOverrideUrl` 返回正文字符串；空 JS 默认读取 document，页面完成后延时执行，空结果按 Kotlin 的阶梯间隔重试。cacheFirst 映射 URLRequest 缓存策略，但每次隔离的非持久 WebKit 数据仓库不能复用 Android 池化 WebView 的跨请求缓存。
- 资源嗅探使用 document-start 注入的 fetch、XHR 包装及 PerformanceObserver，并覆盖 frame；正则整体包装为 `\A(?:表达式)\z`，保留交替分支回溯与全串匹配。iOS 不安装 HTTP/HTTPS WKURLSchemeHandler。无法完整覆盖 Service Worker、页面替换原生函数、未进入 performance 时间线的请求；fetch/XHR 的 URL 在发起时报告，不能证明请求成功，也不提供资源响应字节。
- CookieStore 的请求 Cookie 写入隔离的 WKHTTPCookieStore；完成时按资源域和来源 tag 经统一入口回写。SourceSessionHttpClient 将浏览器 Cookie 在数据库事务中合并进 HTTP 使用的 CookieRepository，新同名值覆盖旧值，并同步 CookieStore；默认 HTTP 重取等待持久化完成，持久化失败则不重取。对应 Kotlin `WebViewActivity.kt:484-488`、`CookieStore.kt:33-38`、`JsExtensions.kt:412-435`。CookieStore 自身仅按可注册域名保存，不能保留所有 path、过期与同名多 Cookie 语义，合并也不传播删除。
- `getVerificationCode` 展示验证码页面并等待非空输入；`startBrowser` 展示后即返回；`startBrowserAwait` 等用户完成后返回当前 document，默认再用普通 HTTP 重取原 URL，可用第三参数 false 关闭重取。取消、退后台均结束等待。交互界面同时限一个，冲突明确报错。
- `java.getWebViewUA()` 使用可注入提供者；App 在前台创建未设置 customUserAgent 的 WKWebView，读取 `navigator.userAgent`，返回真实 WebKit UA。对应 Kotlin `JsExtensions.kt:791-792`，不使用固定 Chrome UA 代替。
- WebKit 保留平台 TLS 校验，不复刻 Android 的忽略 SSL 错误行为；请求附加头不保证传给后续子资源，合成 StrResponse 不保留 Android priorResponse 重定向链。App UI 和 WebKit 真机行为须由主会话构建及设备验证。

## B17：局域网 WebSocket

- 对照 Android `2bdd3c58b` 的 `web/WebSocketServer.kt`、`web/socket/BookSourceDebugWebSocket.kt`、`RssSourceDebugWebSocket.kt`、`BookSearchWebSocket.kt` 与 `api/controller/BookSourceController.kt`。在 B14 的同一个 NWListener 端口升级，原 HTTP API 保持原处理路径。
- `/bookSourceDebug` 的首消息是 `{"tag":"书源 URL","key":"关键字或调试链接"}`；`/rssSourceDebug` 是 `{"tag":"订阅源 URL"}`；`/searchBook` 是 `{"key":"关键字"}`。同一连接的后续业务消息忽略，文本与二进制消息均按 JSON 解析。
- 调试回复为纯文本日志，过滤状态 10、20、30、40；状态 -1、1000 后发送正常关闭帧，原因「调试结束」。搜索每次回复累计 SearchBook JSON 数组，结束原因 `Search finish`。缺少参数回复「不能为空」，源不存在回复「书源不存在」或「订阅源不存在」。非法 JSON 使用 1008，内部调试失败使用 1011。
- 令牌值及是否必需复用 HTTP 配置。浏览器通过 `Sec-WebSocket-Protocol: legado, legado.token.<去填充的 base64url UTF-8 令牌>` 鉴权，响应只选择 `legado`。关闭令牌要求时仍需 `legado` 子协议。与 Android 一致，WebSocket 不使用 HTTP 的 `x-legado-token` 请求头。未通过鉴权返回 HTTP 403，未知 socket 路径返回 404。
- 握手使用 SHA-1 与 Base64 计算 Accept；帧层支持掩码、文本、二进制、跨帧 UTF-8、126/127 扩展长度、穿插 ping/pong 和关闭帧。客户端帧必须掩码，消息上限 4 MiB；协议错误、无效 UTF-8、超限分别使用 1002、1007、1009。未协商扩展，拒绝 RSV 位，不支持压缩。
- 首业务消息期限 10 秒，收到请求后每 30 秒发送 ping。正常主动关闭等待对端 close，最多 5 秒；被动关闭回送对端 close 后释放连接。帧协议错误立即进入不可恢复状态，清空解码缓冲，不再读取或处理远端帧，错误 close 写完后释放连接。断开、退后台、停止服务都取消调试和搜索任务。升级后取消 HTTP 的 120 秒总期限。
- B8 的 SourceDebugger 直接提供书源日志。RSS 使用 B11 的 RssService 解析首个栏目及首篇文章，输出获取成功、列表大小、首项标题/时间/描述/图片/链接诊断、无时间戳空行和内容页起止日志；日志由解析过程发出，沿用 Debug 的时间戳及树形前缀。错误使用 Swift 描述，不复刻 Kotlin 堆栈文本。
- 搜索读取保存的 searchScope、threadCount、precisionSearch：支持分组、单源、全部，范围无匹配时回退全部启用源；按配置并发，每源整体 30 秒超时。空批次仍回调累计结果，同名同作者合并，按精确匹配、分类包含、书名/作者包含、其他排序，前三类同级按来源数降序。Android 此 socket 入口只在首消息建立搜索任务，第一页搜索完成即关闭，不支持后续页；iOS 保持相同生命周期。每个调试连接拥有独立日志流，不复刻 Android 全局 Debug 回调独占及「调试通道占用中」提示。
- 自写页面 `/debug.html` 提供书源 URL、关键字、令牌输入和实时日志；令牌不写入浏览器持久化存储，停止或离开页面关闭连接。
- 验证使用工作区内 SwiftPM、假 HTTP 客户端和可注入会话发送回调，无真实外网请求。iOS 构建、浏览器至设备的真实 TCP 升级和后台切换仍需主会话验证；未运行 xcodebuild 或 XcodeGen。
