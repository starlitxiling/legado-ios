# XPath 兼容性与已知差异

当前 XPath 在 libxml2 树上执行。字符串直接解析；SwiftSoup Element 的 `outerHtml()` 重新交给 libxml2 解析，XPathNode 则保留所属 libxml2 文档。JSoup 字符串缓存中的删除不传入 XPath。
以下 Swift 结果由 `AnalyzeByXPathTests.testKnownBridgeDifferences` 实测；Kotlin 结果依据任务书、`AnalyzeByXPath.kt:17-40` 与 jsoup 语义推导，未运行 Android，不能标记为两端一致性通过。SwiftSoup 对照仅是本机辅助证据。

## 祖先关系丢失

最小输入为 `<div id="p"><a>A</a></div>`，保持原文档存活，以其中的 a 元素为输入执行 `@XPath:../@id`。
Swift 返回 `[]`；原 SwiftSoup 节点的父元素 id 为 `p`；Kotlin 原 Element 路径预期返回 `["p"]`。
影响是父轴、祖先轴以及依赖原树的兄弟关系无法恢复。仅序列化 a 无法保留 div。
后续方案是在 SwiftSoup DOM 上自实现 XPath 求值器，直接保留原节点上下文；本轮不修改桥接结构。

## 表格补全差异

最小输入为 `<table><tr><td>X</td></tr></table>`，规则为 `//table/tbody/tr/td/text()`。
Swift 返回 `[]`，Kotlin/jsoup 预期返回 `["X"]`；本机 SwiftSoup 的 `table > tbody > tr > td` 确实得到 X。
反向规则 `//table/tr/td/text()` 在 Swift 返回 `["X"]`，Kotlin/jsoup 预期为空，因为 jsoup 插入 tbody。
`<td>X</td>` 由 Kotlin 入口及 Swift 桥接补 tr/table 后仍有同类差异，现有测试只记录已知差异，不表示认可一致性。
影响是浏览器或 jsoup 树导出的直接子路径失配；不得通过更改一致性 fixture 期望值消除失败。
后续方案是在 SwiftSoup DOM 上求值，统一采用其 HTML5 树；本轮不添加补标签修补器。

## HTML5 实体

最小输入为 `<a>&hopf;</a>`，规则为 `//a/text()`。
Swift 返回 `["&hopf;"]`；Kotlin/jsoup 预期为 `["𝕙"]`，本机 SwiftSoup 对照确实为该字符。
影响是文本匹配与输出发生差异；后续文本投影的规范空白无法修复此前保留成字面值的实体。
后续方案是在 SwiftSoup 树上求值，避免重复使用不同实体表解析同一份 HTML。

## 元素序列化

最小输入为 `<div><p>X</p></div>`，规则为 `//div`。
Swift 返回 `["<div><p>X</p></div>"]`；SwiftSoup 默认格式为 `"<div>\n <p>X</p>\n</div>"`。
Kotlin/jsoup 默认格式预计接近 SwiftSoup，但 JsoupXpath 2.5.3 的 `asString()` 与 JXNode `toString()` 输出尚未逐字验证，不能把该预计当实测结果。
影响包括换行、缩进、实体转义与空标签格式；html()/outerHtml() 目前也使用 libxml2 序列化。
后续方案是在 SwiftSoup DOM 上求值并使用同一序列化器，再对照 Android 的完整字符串验证。

## 扩展函数核验范围

[JsoupXpath 官方 README 的 NodeTest](https://github.com/zhegexiaohuozi/JsoupXpath#nodetest)区分 text() 自有文本与 allText() 全部文本；num() 从自有文本提取首个连续数字。因此 `<a>A<b>B</b>C</a>` 的 text() 为 `["AC"]`，allText() 为 `["ABC"]`。
实现支持路径末尾的无参 text()/allText()/html()/outerHtml()/num()；扩展嵌套在谓词或函数参数中的语义未完成。num() 的正负号、小数及无数字边界尚未与 2.5.3 对照。
版本核验限制：尝试获取 v2.5.3 的 Text/AllText/Num 源码均返回 Cache miss；本机缓存检索未找到源码，curl 返回无法解析 raw.githubusercontent.com。README 为当前分支，不等同于 2.5.3 源码核验。
