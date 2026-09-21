# XPath DOM 求值与兼容性

P9 默认直接在 SwiftSoup 的 HTML5/XML DOM 上求值。选出的节点保留原文档引用，后续 XPath 与 CSS 继续使用同一个节点；不会再把节点序列化后交给另一套 HTML 解析器。

基线为 Kotlin `2bdd3c58b`，使用 JsoupXpath `2.5.3` 与 jsoup `1.23.2`。已取得上游 tag `v2.5.3`（`ec9f18f0731fdae7d72a9c0b800a77b7968ed74b`）并实际运行 Java 对拍，原始输出 .build/round5/xpath-probe/result.txt。

## 已解决的三项差异

| 输入 / 规则 | 当前输出 | 验证 |
| --- | --- | --- |
| 原文档中 a 的 `../@id` | 原 div 的 id | Swift 单测及 Java 对拍 |
| table 省略 tbody，`//table/tbody/tr/td/text()` | `X` | Swift 单测及 Java 对拍 |
| `<a>&hopf;</a>`，`//a/text()` | `𝕙` | Swift HTML5 DOM 单测 |

序列化由 SwiftSoup 完成，与选择时使用相同的树；XML 保留大小写，HTML 自动补全 tbody，HTML5 实体只解码一次。

## 支持范围

- 绝对/相对路径、属性、通配符、父轴、祖先轴、后代轴、前后兄弟轴、preceding/following；并集去重并恢复文档顺序。
- 数值/位置谓词、分组后过滤、布尔与比较、算术、字符串函数、聚合、id/lang/name/local-name/namespace-uri；反向轴先按轴顺序应用谓词。
- text/allText/html/outerHtml/num 可出现在路径或谓词/函数参数内。保留 JsoupXpath 的包含/前后缀/正则运算符与 sibling/-one 轴。
- 不支持的函数/轴显式报错。需要比较旧结果时可构造 AnalyzeByXPath(useLegacyBridge: true)，默认不会静默转回 libxml2。

## 旧预期纠正与扩展

Java 实测 `<a>A<b>B</b>C</a>` 的 text() 返回 `A, C` 两个文本块，allText() 返回 `ABC`；旧单测把 text() 合并成 AC，现按固定版本的 [Text.java](https://github.com/zhegexiaohuozi/JsoupXpath/blob/v2.5.3/src/main/java/org/seimicrawler/xpath/core/node/Text.java) 修正。

`Price -12.5` 的 num() 实测为 `12.5`，其正则不包含符号，并取全部文本中的第一段数字；旧版 Swift 的负号行为不符合 [Num.java](https://github.com/zhegexiaohuozi/JsoupXpath/blob/v2.5.3/src/main/java/org/seimicrawler/xpath/core/node/Num.java)。

计划所列 tidyText() 并不存在于该上游 tag，Java 实测返回空列表。iOS 按计划增加该名称，定义为 allText() 的规范空白别名；这是明确的兼容扩展，不声称与 Android 此版本一致。

## 验证

Core 全量 732/0；XPath 专项覆盖原树生命周期、三个硬差异、扩展嵌谓词、反向轴、分组、XML、显式旧实现及错误参数。既有合成语料不回退。复审由主会话执行，遵守用户不启用子代理的要求。

应用层回归 318 项通过，generic iOS 构建通过（`p9-xpath-app.log`、`p9-xpath-ios.log`）。
