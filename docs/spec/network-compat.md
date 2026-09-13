# 网络兼容性（阶段 2 U1）

规格基线为 Kotlin `cb664b84d`；网络请求经 `HttpClient` 注入。

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
  这两阶段顺序以 Kotlin `cb664b84d` 为准；关闭 CookieJar 时不执行第二次合并，也不回写响应 Cookie。
- Cookie 同名后值覆盖前值；空值忽略，字符串 null 保留；set 整体覆盖，replace 合并，remove 删除。
- 不提供 Cookie 数据库持久化、会话与持久 Cookie 分层、4096 字节随机淘汰、WebView 同步。
- 响应 Cookie 通过 Foundation 解析；未实现完整过期清理、路径作用域。
- headers 用字典存储，同名头不保留多值顺序，重复 Set-Cookie 受 Foundation 合并行为影响。
- header 名称按 HTTP 大小写不敏感处理；Kotlin 部分分支按 Content-Type 精确键查找。
- 默认 User-Agent 固定使用规格中的 Chrome/153.0.0.0；不读取 Android 偏好设置。
- User-Agent 为精确字符串 null 时删除；其他头的 null 字符串按 Kotlin 保留。
- `dnsIp` / `resolveIp` 保留在 UrlOptions，执行忽略；代理和 Cronet 没有执行支持。
- 代理 / Cronet 不属于现有 UrlOptions 模型字段，书源 header 中的代理信息不建立代理连接。
- `serverID` 是 WebDAV 凭据选择标识，**保留字段，U6 接入**，不是普通 HTTP 服务器转发配置。
  Kotlin `lib/webdav/WebDav.kt:48-50` 从 AnalyzeUrl 读取该值；`lib/webdav/Authorization.kt:25-30` 据此查询服务器配置中的用户名和密码。
- U2 普通 HTTP 不使用 serverID；只有启用 webView 才进入明确报错的 WebView 桩，单独 webJs 在普通 HTTP 路径忽略。
- 宿主 `get/head/post` 的 timeout 缺省为 30,000 ms，0 表示不设超时，负数抛参数错误（`JsExtensions.kt:579-657`）。
  显式 ajax/connect callTimeout 的 0 同样表示不设总超时，负数无效（`AnalyzeUrlNetworkOptions.kt:117-118`）。
  同步宿主将“不设超时”转换为 `TimeInterval.greatestFiniteMagnitude` 传给 U1，避免零总预算在 URLSession 客户端立即失败；
  URLSession 加离线 URLProtocol/ReplayHttpClient 的用例验证了该传递路径，不使用真实网络。
- URL 选项 `,{"timeout":...}` 与上述显式参数不同：只有 1 至 Int32.max 的整数有效，0 或负数视为未设置，回落 U1 默认 60,000 ms，
  依据 `AnalyzeUrlNetworkOptions.kt:12-22`、`AnalyzeUrl.kt:980-981`；不把该分支的 0 当作无限超时。
- `js` / `bodyJs`、type 的十六进制响应、XML 声明补写由上层后续接入，本层不执行。
- 不实现 Android 并发限速器、ZIP 自动解压或 isTest 错误码封装。
