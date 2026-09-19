# 跨会话只读复审发现（轮次 4）

> 原实现与阶段 0–4 的复审全部出自同一个 Codex 通道，从未有独立第二意见。
> 本文件汇总本轮新开的只读复审结论。主会话已抽查 `file:line`，标注「已核验」的是亲自看过代码确认的。
> 路径省略公共前缀：Swift 为 `Packages/LegadoCore/Sources/LegadoCore/`，Kotlin 为 `app/src/main/java/io/legado/app/`。

## C5a · AnalyzeRule + jsoup 私有语法（session `01a0a053-e06b-74a2-97ca-12dd279f84b5`）

### P0

1. **组合符被切分两次，改变混合组合规则的含义。**
   分派层与 jsoup 层都按 `||` 切一遍。触发：`getString("@CSS:p@text&&p@id||x")` 对 `<p id="B">A</p>`，
   Kotlin 得 `A`（第二项读属性 `id||x`），Swift 得 `A\nB`。
   Swift `AnalyzeRule/AnalyzeRule.swift:237,251`、`AnalyzeByJSoup/AnalyzeByJSoup.swift:71`；
   Kotlin `model/analyzeRule/RuleAnalyzer.kt:191`、`AnalyzeByJSoup.kt:90`。
2. **映射内容缺少直接取键分支。** 内容为字典且规则为 `name` 时，Kotlin 直接返回该键的值且只用第一段规则，
   Swift 仍走 jsoup 路径取不到。
   Swift `AnalyzeRule/AnalyzeRule.swift:175,230`、`AnalyzeByJSoup/AnalyzeByJSoup.swift:18`；Kotlin `AnalyzeRule.kt:245,337`。
3. **`isURL` 只切换取值方式，未做 URL 末处理。** Kotlin 返回绝对地址并在空结果时回退基址，Swift 返回相对地址。
   Swift `AnalyzeRule/AnalyzeRule.swift:108,114,205`；Kotlin `AnalyzeRule.kt:374`。
   **已核验但存疑**：`AnalyzeRule.swift:107` 的注释写明「URL 后处理留给宿主集成层」，说明这可能是有意的分层决策。
   返修前必须先查清宿主集成层是否已补偿；若已补偿则本条降级为文档问题。

### P1

4. **CSS 组合规则的空片段不抛异常。** `@CSS:p@text&&` 在 Kotlin 抛异常，Swift 返回文档 `data()` 继续执行。
   Swift `AnalyzeRule/SelectorEngine.swift:26`、`AnalyzeByJSoup/AnalyzeByJSoup.swift:69`；Kotlin `AnalyzeByJSoup.kt:91`。
5. **空结果集上的区间索引提前返回，吞掉越界异常。** 无 `li` 时求值 `tag.li[0:-1]`，Kotlin 抛异常，Swift 返回空数组。
   Swift `AnalyzeByJSoup/JSoupIndex.swift:89`；Kotlin `AnalyzeByJSoup.kt:348,354,391`。
6. **`setContent(nil)` 不拒绝。** Kotlin 抛 `AssertionError`，Swift 接受并在后续返回空结果，掩盖内容缺失。
   Swift `AnalyzeRule/AnalyzeRule.swift:38,176`；Kotlin `AnalyzeRule.kt:105`。

### 未覆盖

`RuleAnalyzer` 的底层切分实现不在本次范围内（括号嵌套、引号、反斜杠、UTF-16 游标未核对）；
HTML4 实体表未与 Apache Commons Text 逐项比对；Java 与 ICU 正则方言差异未验证。

## C5c · JS 宿主层（session `01a0a053-f5c9-7f83-a4af-c1337823aa60`）

### P0

1. **`java.getString(rule, null, true)` 直接抛未实现。** `getString` 是一级高频入口（语料中 276 个书源使用）。
   **已核验**：`JsEngine/JavaHost.swift:202` 为 `guard let isUrl = boolean(2), !isUrl else { throw JsEngineError.unimplemented(...) }`。
   Kotlin `model/analyzeRule/AnalyzeRule.kt:302` 有 `isUrl` 参数并向下传递。与 C5a 第 3 条是同一个缺口的两端。
2. **`getStringList` 静默丢弃第二、第三参数。**
   **已核验**：`JavaHost.swift:205` 为 `case "getStringList": return try analyzer().getStringList(string(0))`，
   传入内容与 `isUrl` 都被忽略，脚本会拿到当前内容而非传入内容。Kotlin `AnalyzeRule.kt:205`。
3. **编码类方法不校验空参数。** `java.md5Encode(null)` / `base64Encode(null)` 在 Kotlin 因非空参数声明而失败，
   书源作者靠 `catch` 做回退；Swift 先做通用字符串转换再计算，不抛错，导致回退失效。
   Swift `JavaHost.swift:216,221`；Kotlin `help/JsEncodeUtils.kt:22`、`help/JsExtensions.kt:705`。

### P1

4. **`base64Decode` 把字符替换行为改成异常。** `java.base64Decode('/w==', 0)` 在 Kotlin 用 `String(bytes)` 替换非法 UTF-8，
   Swift 可失败构造返回 nil 后抛错。Swift `JavaHost.swift:252`；Kotlin `utils/EncoderUtils.kt:31`。
5. **字符集白名单缺 JVM 标准字符集与别名。** `encodeURI('中文','UTF-16')` Kotlin 正常编码，Swift 返回空串。
   Swift `JavaHost.swift:257,272`；Kotlin `JsExtensions.kt:681,761`。
6. **void 宿主方法统一转成 JS `null` 而非 `undefined`。** 影响 `typeof` 与 `=== undefined` 判断。
   Swift `JsEngine/JavaHostNetwork.swift:37`、`JavaHost.swift:147`；Kotlin `help/CacheManager.kt:60`。未运行验证。

### 宿主方法覆盖缺口

Kotlin 两个接口共 **104** 个方法名，Swift 白名单 **34** 个。缺失项里非零使用的（按语料使用源数）：

| 方法 | 使用源数 | 档位 |
| --- | --- | --- |
| `longToast` | 28 | 二级 |
| `base64DecodeToByteArray` | 16 | 二级 |
| `t2s`（繁转简） | 16 | 二级 |
| `createSymmetricCrypto` | 15 | 二级 |
| `timeFormatUTC` | 9 | 二级 |
| `getWebViewUA` | 6 | 三级（转交范围外实现） |
| `randomUUID` | 6 | 三级 |
| `HMacHex` | 5 | 三级 |
| `androidId` / `desEncodeToBase64String` | 各 4 | 三级 |
| `digestHex` / `queryBase64TTF` / `queryTTF` / `replaceFont` / `s2t` | 各 3 | 三级 |
| `md5Encode16` | 2 | 三级 |
| 其余约 15 个 | 各 1 | 三级 |

零使用的三级项约 60 个，按既定分级策略继续挂起。

### 未覆盖

WebView 实际参数与主线程调度跨单元未展开；`HostAsyncBridge` 确实阻塞调用线程且无独立截止时间，
是否形成主线程死锁取决于范围外服务，未验证；未取得 Hutool / Rhino 依赖源码，无 flags 的 Base64 语义与 AES 全模式未确认。

## 待办

- C5b（JSONPath / XPath 求值器）尚未开审。
- 上述 P0 的返修依赖 `tools/conformance-run`（单元 C6）先建立可验证回路 —— 本机无 XCTest，
  否则任何修改都只能停留在「编译通过」。
