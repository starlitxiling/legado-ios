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

- **Android 基线未跑**：本机没有 JDK 与 Android SDK，阶段 0 完成判据「语料在 Android 端一键跑出全绿基线」未达成。合成用例的期望值全部按规格推导，标 `spec-derived, not run on Android`，需要装环境后校正一次才能升为黄金。人类尚未决定是否安装。
- **规格仍有 7 条待实测**：JsonPath 无 `$` 前缀是否自动补、jsoup 属性名大小写、`Element.data()` 返回值、Kotlin 正则替换串转义、`%.0f` 边界、URL 编码字符集、JsoupXpath 扩展函数集。
- **review 同模型**：本会话项目级 agent 定义未加载，所有 review 由 Codex 完成，Codex 实现的单元也由 Codex 独立上下文复审，跨模型交叉要等下个会话 Opus@high 可用后补。
- **嵌套 Package 的 `.gitignore`**：根 `.gitignore` 的 `.swiftpm/xcode/` 匹配不到 `Packages/LegadoCore/` 下的同名目录，已在 Package 目录单独加。

## 后续 TODO

1. 人类决定是否安装 JDK 21 + Android SDK；装了就补「Android 基线跑批」脚本，校正 100 条合成用例。
2. 阶段 1 单元 1（`RuleAnalyzer`）已实现待复审；后续单元按规格章节推进：`AnalyzeRule` 六模式分派与 `##` / `{{}}` / `@get` / `@put`，`AnalyzeByJSoup`（SwiftSoup）私有语法，XPath（Kanna），JSONPath，正则，`AnalyzeUrl` 选项解析，JS 宿主一级 16 个方法。
3. 一致性用例运行器：让 `swift test` 直接消费 golden 与 synthetic JSON，按 kind 分派到对应引擎入口。
4. 下个会话先实际起一次 `opus-explorer` 确认项目级定义已加载，恢复「Codex 实现、Opus 复审」交叉。
5. `ios` 分支推送到远端与 labels 同步均为对外动作，待人类同意。
