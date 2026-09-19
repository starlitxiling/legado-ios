<subagent_contract>
你是一个子代理。你的最后一条消息是唯一交付物，调用方看不到其他任何内容。必须遵守：
1. 所有发现、结论、文件路径都写进最后一条消息；禁止以计划、提问或"接下来我会…"收尾——先做完，再汇报。
2. 第一段先给结论（发生了什么/发现了什么），细节放后面。
3. 涉及代码的每条论断都带 `文件绝对路径:行号` 引用。
4. 如实汇报：没验证过的事不得声称完成；不确定就标注"未验证"。
5. 只做指派的任务：不扩 scope、不顺手重构、不 commit/push。
6. 用完整句子；禁止碎片化短语、箭头链（A→B）、自造缩写和代号、表情符号。
7. 被卡住就停下，精确说明缺什么信息；不许猜测、不许编造。
</subagent_contract>

<task>
目标：轮次 4 单元 C5b —— 对 iOS 重写版的 **JSONPath 与 XPath 两个求值器**做只读一致性复审，逐条对照 Kotlin 原实现找出行为差异。这是本工程第一次对该模块做独立复审：原实现与既有复审都出自同一个 Codex 通道，本次是**新会话、无先验**的第二意见，请以「这段代码很可能有你尚未发现的偏差」为前提工作。

工作目录：/Users/xiling/Work/legado-ios/.claude/worktrees/ios

**这是只读任务：禁止修改任何文件，禁止 git 写操作，禁止跑构建与测试。**
（注意：另有子代理正在并行修改 `Packages/LegadoCore/Sources/LegadoCore/Backup/` 与 `Tests/`，工作树是脏的。
那些改动与本任务无关，不要看、不要评论、更不要动。）

## 背景

Legado 是 Android 开源小说阅读器，书源规则里可以用 JSONPath（`@json:` 前缀）与 XPath（`@XPath:` 或 `//` 前缀）抽取内容。
Kotlin 侧是**可执行规格**，iOS 侧的任何行为差异都会导致真实书源解析出错。

Android 端这两者依赖第三方库：JSONPath 用 `com.jayway.jsonpath`，XPath 用 `cn.wanghaomiao.xpath`（JsoupXpath）。
iOS 侧的处理路线不同：JSONPath 是**自研实现**，XPath 是**桥接到 Kanna**。因此「实现方式不同」本身不是发现，
**差异必须落到可观察的输入输出行为上**才算数。

## 复审目标（Swift，本次范围）

- `Packages/LegadoCore/Sources/LegadoCore/AnalyzeByJSonPath/`：`AnalyzeByJSonPath.swift`、`JsonPathParser.swift`、
  `JsonPathEvaluator.swift`、`JsonPathPredicate.swift`、`JsonPathJSON.swift`（约 700 行）
- `Packages/LegadoCore/Sources/LegadoCore/AnalyzeByXPath/`：`AnalyzeByXPath.swift`、`XPathNode.swift`、`XPathProjection.swift`（约 170 行）

**范围之外的目录不要看**（AnalyzeRule、AnalyzeByJSoup、JsEngine、AnalyzeUrl 由其他单元负责），
但若发现依赖它们的接口契约，可引用签名并标注「跨单元」。

## Kotlin 规格真源（只读）

路径前缀 `/Users/xiling/Work/legado-ios/app/src/main/java/io/legado/app/`（Kotlin 自 commit 2bdd3c58b 起未变动）。
对应实现在 `model/analyzeRule/` 下的 `AnalyzeByJSonPath.kt` 与 `AnalyzeByXPath.kt`。
**自己去定位，不要相信本任务书给的文件名是完整的。**

## 重点审查项

逐条给出「Kotlin 怎么做 / Swift 怎么做 / 是否等价」：

### JSONPath

1. **语法覆盖面**：`$`、`.`、`..`（递归下降）、`[*]`、`[n]`、`[-n]`、`[start:end]`、`[a,b]`、`['key']`、
   通配 `*`、过滤表达式 `[?(@.x == 'y')]` 的运算符集合（`==` `!=` `>` `<` `>=` `<=` `=~` `in` `nin` `size` `empty`）、
   逻辑组合 `&&` `||`、函数（`length()` 之类）。列出 jayway 支持而 Swift 不支持的，以及 Swift 支持但语义不同的。
2. **返回形态**：单值与列表的判定，`getString` 与 `getStringList` 在各自路径上的取值差异；
   路径不存在时返回空串、nil 还是抛异常；结果是对象或数组时如何字符串化（这一项最容易出偏差）。
3. **类型宽松度**：数字与字符串比较、布尔与字符串比较、null 的处理；jayway 默认是宽松还是严格。
4. **多规则组合**：`{$.a}` 模板插值、`||` 与 `&&` 在 JSONPath 模式下的语义是否与默认模式一致。

### XPath

5. **Kanna 桥接的覆盖面**：Kotlin 用 JsoupXpath，其扩展函数集（`text()`、`allText()`、`html()`、`num()` 等）
   在 Kanna 上是怎么实现的、哪些没实现、没实现时的行为（抛错还是静默返回空）。
6. **轴与谓词**：常用轴（`child`、`descendant`、`following-sibling`、`parent`、`ancestor`）与谓词在两侧是否等价；
   `//a[1]` 这类索引语义（XPath 是 1 基）在 Swift 侧是否被错误地当成 0 基。
7. **属性与节点取值**：`@href`、`text()`、`string()`、节点集转字符串的规则；空结果的返回形态。
8. **异常语义**：非法 XPath 表达式在两侧分别是抛错还是返回空。

## 已知的、不算发现的事项（不要重复报告）

先读 `docs/spec/xpath-compat.md` 与 `docs/spec/rule-engine.md`。已登记的差异不算新发现，
特别是：Kanna 与 jsoup 的**祖先关系与 table 结构补全差异**已被明确接受，
**自研 XPath 求值器已列为触发式 TODO**（即已知 Kanna 不完全等价，不需要你再论证一遍这个大方向）。
但若你认为某条已登记差异的定级过低（实际会影响常见书源），可以单独指出并说明理由。
编译告警（`try` 冗余等）已知，不必报告。

## 交付格式

中文 markdown，不超过 90 行。结构：

1. **结论**：一段话说清两个求值器各自的一致性水平，以及最该先修的三条。
2. **发现清单**：分 JSONPath 与 XPath 两组，按 P0（会导致错误解析结果或崩溃）/ P1（边界行为不一致）/ P2（可维护性）分级。
   每条必须同时给 `Swift 文件绝对路径:行号` 与 `Kotlin 文件绝对路径:行号`，并写明「触发条件」——
   什么样的规则字符串配什么样的 JSON 或 HTML 输入会让这个差异实际暴露。没有可触发条件的猜测不要写。
3. **JSONPath 语法覆盖表**：jayway 语法特性 / Swift 是否支持 / 不支持时的行为，紧凑表格。
4. **已核对且确认一致的要点**：列条目名即可。
5. **未覆盖 / 不确定项**。

**不要回灌大段源码**，单条引用不超过 5 行。
</task>
