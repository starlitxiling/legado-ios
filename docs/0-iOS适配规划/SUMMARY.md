# 总结：iOS 适配规划与阶段 0 规格化

## 开发项背景

本仓库是 Legado（Android 开源小说阅读器）的活跃分支，目录名带 `ios` 却没有一行 iOS 代码。上游 `gedoor/legado` 已于 2026-05 清空代码只留侵权公告，同类 iOS 应用均已从 App Store 下架。要解决的问题：在知情接受法律与分发风险的前提下，给出可执行的 iOS 适配路线，并把「兼容现有社区书源」这一核心要求变成可验证的契约，而不是靠感觉移植。

## 实现方案

**路线拍板**（`PLAN.md` §7）：纯 Swift 重写 + 一致性测试集，Kotlin 端只当可执行规格；自签侧载分发；最低 iOS 17，Universal；iOS 代码放本仓库 orphan 分支 `ios`。否掉 KMP 共享内核的硬理由是 jsoup / JsoupXpath / Rhino / OkHttp 在 Kotlin/Native 上全部不可用，且 KMP 侧没有 XPath 库。

**阶段 0 产物**（全部在 `ios` 分支，commit `ad042b55d`、`e568619f6`）：

| 产物 | 内容 | 核验 |
| --- | --- | --- |
| `docs/spec/rule-engine.md` | 规则引擎语言无关规格，368 行、96 处 Kotlin 行号引用，7 条「未确定需实测」 | Codex 跨模型审出 6 处与源码不符，已修并复审；主会话核实 3 条 |
| `Tests/Conformance/fixtures/golden/` | 从 Kotlin 测试断言逐字搬运的 42 条黄金用例（6 个测试类） | Codex 复审抽 6 条 + 主会话抽 1 条，逐字一致 |
| `Tests/Conformance/fixtures/synthetic/` | 按规格推导的 100 条合成用例，覆盖 Default 索引、组合符、替换、模板、XPath / JSONPath / 正则前缀、URL 选项、空边界 | Codex 独立复审抽 43 条 clean；期望值标 spec-derived |
| `docs/0-iOS适配规划/宿主API优先级.md` + `tools/corpus/` | 4063 个去重公开书源的静态统计：961 个用 `java.*`；一级 16 个方法覆盖 80%，二级 31 个覆盖 95%；E4X 零使用，`Packages.` 1.3%，`.length()` 1 例 | 词表扩到 157 名后词表外仅 3 个调用名；9 个单测通过 |
| 项目骨架 | README / CLAUDE.md / DEVTREE / labels / `.claude/agents/` 五个 Opus@high 定义 / PROGRESS.md | Codex 两轮 review，4 条规则矛盾已修 |

**工作模式**：主会话只统筹，子 agent 只允许 Opus@high（仓库 `.claude/agents/` 定义）或 Codex `gpt-6-astra` @ medium；每步更新 `PROGRESS.md` 做断点续传。本轮实际执行中，四个原生子 agent 因额度 429 中断，产物作废后全部改由 Codex 重做。

**决策留痕**：语料只提交合成 fixture 与聚合统计，不把第三方站点内容和整套书源合集带进仓库；合集缓存在会话 scratchpad，来源仓库 / 路径 / commit 记录在统计文档顶部，脚本可重跑。

## 局限性

- **Android 基线未跑**：本机没有 JDK 与 Android SDK，阶段 0 完成判据「语料在 Android 端一键跑出全绿基线」未达成。人类决定不安装（PLAN §7），合成用例的期望值全部按规格与 Kotlin 源码推导，标 `spec-derived, not run on Android`，正确性靠逐条回源复审保证。
- **规格仍有待实测项**：jsoup 属性名大小写、`Element.data()` 返回值、Kotlin 正则替换串转义、`%.0f` 边界、URL 编码字符集；JsonPath 无 `$` 前缀自动补 `$.`（阶段 1 已按 jayway 源码核清）与 JsoupXpath 扩展函数集（按其 README 实现）已有结论。
- **review 同模型**：本会话项目级 agent 定义未加载，所有 review 由 Codex 完成，Codex 实现的单元也由 Codex 独立上下文复审，跨模型交叉要等下个会话 Opus@high 可用后补。
- **嵌套 Package 的 `.gitignore`**：根 `.gitignore` 的 `.swiftpm/xcode/` 匹配不到 `Packages/LegadoCore/` 下的同名目录，已在 Package 目录单独加。

## 后续 TODO

1. 阶段 2（轮次 1）：网络层、java 宿主网络方法、BookSource 导入、WebBook 流程、GRDB 与备份导入，见 `docs/1-阶段2数据与网络/PLAN.md`。
2. 下个会话先实际起一次 `opus-explorer` 确认项目级定义已加载，对阶段 1 的 8 个单元补 Opus 交叉复审。
3. 在 SwiftSoup DOM 上自研 XPath 求值器，根治桥接的祖先关系与 table 补全差异（触发条件：真实书源回归暴露）。
4. labels 同步远端为对外动作，待人类同意。

## 阶段 1 增补（2026-09-13）

规则引擎核心 `Packages/LegadoCore` 以 8 个开发单元落地，每个单元 Codex 实现、Codex 独立上下文复审、按 Kotlin 返修后提交，累计修正 45 条与 Kotlin 不一致的 finding：

| 单元 | 内容 | 依赖 | 复审 finding |
| --- | --- | --- | --- |
| 1 | `RuleAnalyzer` 切分器（UTF-16 游标） | 无 | 10 |
| 2 | `UrlOptions` 选项解析 + 一致性运行器 | 无 | 3 |
| 3 | `AnalyzeRule` 词法 / 替换 / 变量 / 正则 / 合并 | 无 | 6 |
| 4 | `AnalyzeByJSoup`（SwiftSoup 2.13.9） | SwiftSoup | 3 |
| 5 | `JsEngine` + `JavaHost` 一级离线子集 | JavaScriptCore | 7 |
| 6 | `AnalyzeByJSonPath`（jayway 语义子集，保序 JSON） | 无 | 4 |
| 7 | `AnalyzeByXPath`（Kanna 6.1.0 桥接） | Kanna | 5（2 记已知差异） |
| 8 | `HtmlFormatter` | 无 | 1 |

结果：121 项 XCTest 0 失败；一致性用例 142/142 通过，8 条 UI 预览逻辑标 unsupported。已知差异记录在 `docs/spec/js-host-compat.md` 与 `docs/spec/xpath-compat.md`。工具链因 SwiftSoup 升到 swift-tools-version 6.0（语言模式 5）。

局限：全部期望值仍是规格 / Kotlin 推导，未在 Android 端实测（人类决定不装 SDK）；所有复审为 Codex 同模型独立上下文，Opus 交叉复审待项目级 agent 定义在下个会话生效后补；XPath 桥接的祖先关系与 table 补全差异按 6.87% 使用率接受，自研求值器列入后续 TODO；HTML pretty-print 与 jsoup 的逐字符一致性未验证。
