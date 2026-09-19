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
目标：轮次 4 单元 C5a —— 对 iOS 重写版规则引擎的**规则分派层与 jsoup 私有语法层**做只读一致性复审，逐条对照 Kotlin 原实现找出行为差异。这是本工程第一次对该模块做独立复审：原实现与既有复审都出自同一个 Codex 通道，本次是**新会话、无先验**的第二意见，请以「这段代码很可能有你尚未发现的偏差」为前提工作。

工作目录：/Users/xiling/Work/legado-ios/.claude/worktrees/ios

**这是只读任务：禁止修改任何文件，禁止 git 写操作，禁止跑构建与测试。**

## 背景

Legado 是 Android 开源小说阅读器，书源用一套私有规则 DSL 描述抓取方式。本仓库 `ios` 分支是它的纯 Swift 重写。
Kotlin 侧是**可执行规格**，iOS 侧的任何行为差异都会导致真实书源解析出错。

本机只有 Command Line Tools 没有 Xcode，`XCTest` 不存在，**因此不要试图跑测试**；本任务也不需要跑。

## 复审目标（Swift，本次范围）

- `Packages/LegadoCore/Sources/LegadoCore/AnalyzeRule/`（`AnalyzeRule.swift`、`SourceRule.swift`、`RuleReplace.swift`、
  `AnalyzeByRegex.swift`、`SelectorEngine.swift`、`HTML4Entities.swift`）
- `Packages/LegadoCore/Sources/LegadoCore/AnalyzeByJSoup/`（`AnalyzeByJSoup.swift`、`JSoupIndex.swift`）

合计约 1280 行。**范围之外的目录不要看**（JsEngine、AnalyzeByXPath、AnalyzeByJSonPath、AnalyzeUrl 由其他单元负责），
但若你的发现依赖它们的接口契约，可以引用其签名并标注「跨单元」。

## Kotlin 规格真源（只读）

路径前缀 `/Users/xiling/Work/legado-ios/app/src/main/java/io/legado/app/`（Kotlin 自 commit 2bdd3c58b 起未变动）。
对应实现主要在 `model/analyzeRule/` 下：`AnalyzeRule.kt`、`SourceRule`（可能在 AnalyzeRule.kt 内）、`AnalyzeByJSoup.kt`、
`AnalyzeByRegex.kt`、`RuleAnalyzer.kt` 等；相关工具在 `utils/` 下。**自己去定位，不要相信本任务书给的文件名是完整的。**

## 重点审查项

逐条给出「Kotlin 怎么做 / Swift 怎么做 / 是否等价」：

1. **规则字符串的切分与转义**：`@@`、`@`、`||`、`&&`、`%%`、`{{ }}`、`<js>…</js>`、`@js:`、`##`（正则替换）的
   优先级、嵌套、转义与空片段处理；边界输入（空规则、只有分隔符、分隔符出现在引号或括号内）。
2. **六种模式的分派判定**：默认模式、`@css:`、`@json:`、`@XPath:` / `//`、`:` 前缀正则、JS 模式的识别顺序与大小写敏感性；
   识别失败时的回退路径。
3. **jsoup 私有语法**：`class.xxx.n`、`id.xxx`、`tag.xxx.n`、`text.xxx`、`children`、`@attr`、`@text`、`@ownText`、
   `@textNodes`、`@html`、`@all` 等关键字；**负数索引与索引越界**的语义；`.n` 索引是 0 基还是 1 基；
   多段选择器的逐级求值顺序；结果为空时返回空串还是 nil。
4. **索引与区间语法**：`[0]`、`[-1]`、`[1:3]`、`[1,3,5]`、`!0` 排除语法等在 Kotlin 与 Swift 的解析与越界行为是否一致。
5. **正则替换 `##pattern##replacement###`**：分组引用语法、`$1` 与 `\1`、替换全部还是首个、
   第三个 `###` 的存在与否如何改变语义。
6. **HTML 实体解码**：`HTML4Entities.swift` 的表与 jsoup / Kotlin 侧实际用的解码路径是否一致；
   数字实体、十六进制实体、无分号实体的处理。
7. **字符串清理**：首尾空白、全角空格、`&nbsp;`、换行合并的处理时机与顺序（差一步就会导致正文首尾多余空行）。
8. **异常语义**：Kotlin 抛异常的地方 Swift 是否也抛；Kotlin 吞掉异常返回空的地方 Swift 是否也吞。
   **静默吞掉本该抛出的错误，和抛出本该吞掉的错误，都算 P1。**

## 已知的、不算发现的事项（不要重复报告）

- Swift 侧用 SwiftSoup 替代 jsoup，两者在祖先关系与 table 结构补全上的差异已被记录并接受，见 `docs/spec/xpath-compat.md` 与 `docs/spec/rule-engine.md`。
- HTML pretty-print 与 jsoup 的逐字符一致性未验证，已在交接文档列为已知项。
- 编译告警（`try` 冗余、`CC_MD5` 弃用）已知，不必报告。

先读 `docs/spec/rule-engine.md` 了解已记录的差异，避免把已知差异当新发现。

## 交付格式

中文 markdown，不超过 90 行。结构：

1. **结论**：一段话说清整体一致性水平，以及最该先修的三条。
2. **发现清单**：按 P0（会导致错误解析结果或崩溃）/ P1（边界行为不一致）/ P2（可维护性）分级，每条一行到三行，
   必须同时给 `Swift 文件绝对路径:行号` 与 `Kotlin 文件绝对路径:行号`，并写明「触发条件」——
   什么样的规则字符串或 HTML 输入会让这个差异实际暴露出来。没有可触发条件的猜测不要写。
3. **已核对且确认一致的要点**：列条目名即可，用于界定复审覆盖面。
4. **未覆盖 / 不确定项**：明确说哪些地方你没看透或无法在不运行代码的情况下判定。

**不要回灌大段源码**，单条引用不超过 5 行。
</task>
