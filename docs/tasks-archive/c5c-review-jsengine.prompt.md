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
目标：轮次 4 单元 C5c —— 对 iOS 重写版的 **JavaScript 宿主层**（书源 JS 规则的执行环境）做只读一致性复审，逐条对照 Kotlin / Rhino 原实现找出行为差异。这是本工程第一次对该模块做独立复审：原实现与既有复审都出自同一个 Codex 通道，本次是**新会话、无先验**的第二意见，请以「这段代码很可能有你尚未发现的偏差」为前提工作。

工作目录：/Users/xiling/Work/legado-ios/.claude/worktrees/ios

**这是只读任务：禁止修改任何文件，禁止 git 写操作，禁止跑构建与测试。**

## 背景

Legado 的书源规则里可以内嵌 JavaScript（`<js>…</js>`、`@js:`、纯 JS 书源），脚本里能调用一组宿主方法
（Kotlin 侧叫 `JsExtensions`，在脚本里通过 `java.xxx()` 访问，例如 `java.ajax`、`java.getString`、`java.base64Decode`、
`java.cacheFile`、`java.timeFormat` 等）。Android 用 Rhino 执行，iOS 重写版改用 JavaScriptCore。
**宿主方法的签名、返回类型、空值与异常语义必须与 Kotlin 一致**，否则大量真实书源会静默产出错误结果。

本机只有 Command Line Tools 没有 Xcode，`XCTest` 不存在，**因此不要试图跑测试**；本任务也不需要跑。

## 复审目标（Swift，本次范围）

`Packages/LegadoCore/Sources/LegadoCore/JsEngine/` 全部四个文件：
`JsEngine.swift`、`JavaHost.swift`、`JavaHostNetwork.swift`、`HostAsyncBridge.swift`（合计约 760 行）。

**范围之外的目录不要看**（AnalyzeRule、AnalyzeByJSoup、AnalyzeByXPath、AnalyzeByJSonPath、AnalyzeUrl 由其他单元负责），
但若发现依赖它们的接口契约，可引用签名并标注「跨单元」。

## Kotlin 规格真源（只读）

路径前缀 `/Users/xiling/Work/legado-ios/app/src/main/java/io/legado/app/`（Kotlin 自 commit 2bdd3c58b 起未变动）。
主要对照 `help/JsExtensions.kt`（宿主方法全集）与 `help/CacheManager.kt`、`utils/` 下被它调用的工具；
JS 引擎封装在 Gradle 模块 `:modules:rhino`（路径 `/Users/xiling/Work/legado-ios/modules/rhino/`）与 `help/coroutine/` 附近。
**自己去定位，不要相信本任务书给的文件名是完整的。**

另有一份优先级表 `docs/0-iOS适配规划/宿主API优先级.md`（在 master 工作树的 `docs/` 下，也可在本 worktree 的同名路径找到），
记录了各宿主 API 在真实书源语料里的使用频率。**复审时按使用频率排序**：高频 API 的偏差比低频的重要得多。

## 重点审查项

逐条给出「Kotlin 怎么做 / Swift 怎么做 / 是否等价」：

1. **宿主方法覆盖面**：Kotlin `JsExtensions` 暴露了哪些方法，Swift 侧实现了哪些、缺了哪些、
   哪些是桩实现（调用即抛错或返回空）。缺失项按上面的使用频率表排优先级。
2. **返回类型与 JS 端可见形态**：Kotlin 返回 `String` / `ByteArray` / `Response` / `null` 的方法，
   在 JavaScriptCore 里变成了什么（`undefined` 还是 `null`？字节数组怎么表示？对象属性名是否一致？）。
   **JS 侧 `typeof` 与真值判断的差异是高频书源出错的常见根因**，重点看这一项。
3. **同步与异步**：Kotlin 的宿主方法多数是**阻塞同步**的（脚本里直接 `var r = java.ajax(url)` 拿结果）。
   Swift 侧用 `HostAsyncBridge` 把 async 桥接成同步调用，审查这个桥接：
   是否可能死锁、是否可能在主线程阻塞、超时如何处理、失败时脚本看到的是异常还是空值。
4. **异常语义**：Kotlin 抛 Java 异常时脚本能 `try/catch` 到什么；Swift 侧抛出的是 JS 异常还是静默返回 undefined。
   **静默吞掉本该抛出的错误算 P0**，因为书源作者依赖 catch 做回退。
5. **全局对象与上下文**：`java`、`source`、`book`、`result`、`baseUrl`、`cookie`、`cache` 等注入到脚本作用域的绑定，
   名字、可写性、跨次调用的生命周期与隔离（一个书源的脚本能否污染另一个书源的上下文）是否与 Kotlin 一致。
6. **字符串与编码**：`base64Decode` / `encodeURI` / `md5Encode` / 各种 `strToBytes` 类方法对非 ASCII 与非法输入的行为；
   GBK 等中文编码的往返。
7. **网络宿主方法**（`JavaHostNetwork.swift`）：`ajax`、`connect`、`post`、`webView` 等的参数解析、
   header 合并、cookie 读写、重定向与超时，是否与 Kotlin 侧一致。
8. **资源与安全**：脚本执行有无超时或中断机制（恶意或死循环书源）；JSContext 的复用与释放有无泄漏。

## 已知的、不算发现的事项（不要重复报告）

- 部分宿主 API 按规划分三级实现，低优先级的有意未实现；先读 `docs/spec/js-host-compat.md`，
  **已在该文档中登记的差异不算新发现**，但如果你认为某条登记的差异定级过低（实际影响高频书源），可以单独指出并说明理由。
- 编译告警（`try` 冗余、`CC_MD5` 弃用）已知，不必报告。

## 交付格式

中文 markdown，不超过 90 行。结构：

1. **结论**：一段话说清整体一致性水平，以及最该先修的三条。
2. **发现清单**：按 P0（会导致错误结果、崩溃或死锁）/ P1（边界行为不一致）/ P2（可维护性）分级，每条一行到三行，
   必须同时给 `Swift 文件绝对路径:行号` 与 `Kotlin 文件绝对路径:行号`，并写明「触发条件」——
   什么样的书源脚本会让这个差异实际暴露出来。没有可触发条件的猜测不要写。
3. **宿主方法覆盖表**：Kotlin 有 / Swift 有或缺 / 使用频率档位，一行一个，可压缩成紧凑表格。
4. **已核对且确认一致的要点**：列条目名即可。
5. **未覆盖 / 不确定项**。

**不要回灌大段源码**，单条引用不超过 5 行。
</task>
