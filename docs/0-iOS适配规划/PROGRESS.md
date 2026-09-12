# 进度（阶段 0 · 立项与规格化）

> 新会话先读本文件。最后更新：2026-09-13 03:10（本机时钟）

## 1. 当前位置

- 阶段 0，轮次 0。分支 `ios`（orphan，worktree `.claude/worktrees/ios`），最新 commit `ef6658936`（单元 2）；单元 1 为 `792789b4b`；master 最新 `35a485ed3`。
- 分发 / 路线 / 范围决策已全部拍板，见 `PLAN.md` §7。
- 子 agent 硬规则：只允许 Opus@high（仓库 `.claude/agents/` 定义，**下个会话才生效**）或 Codex `gpt-6-astra` @ medium；本会话只能用 Codex。规则见 `CLAUDE.md`「子 agent 通道」。
- 2026-09-12 16:10 左右四个原生子 agent（两路 review、黄金用例、语料统计）因额度 429 中断，产物作废，改派 Codex 重做。

## 2. 任务表

| 任务 | 状态 | 通道 | 产物 | 验证 |
| --- | --- | --- | --- | --- |
| 项目骨架（README / CLAUDE / DEVTREE / labels / gitignore） | 完成（ad042b55d） | 原生 general-purpose | 根目录 16 文件 | 主会话已抽查结构与 area 标签 |
| 规则引擎语言无关规格 | 完成（ad042b55d） | 原生 general-purpose + Codex 修正 | `docs/spec/rule-engine.md`（368 行，96 处源码引用） | Codex 跨模型审出 6 处与源码不符已修并复审通过；主会话核实 3 条 |
| Kotlin 测试 → 黄金用例 JSON | 完成（ad042b55d） | Codex | `Tests/Conformance/fixtures/golden/`（6 文件 42 条） | Codex 复审抽 6 条 + 主会话抽 1 条，期望值逐字一致 |
| 公开书源语料频率统计 + 宿主 API 优先级表 | 完成（ad042b55d；r2 修正词表与选项解析，9 单测通过） | 主会话下载 + Codex | `tools/corpus/analyze_sources.py`、`docs/0-iOS适配规划/宿主API优先级.md` | 待抽查统计口径 |
| Android 基线运行环境（JDK 21 + Android SDK） | 已决：不装（PLAN §7） | — | — | 期望值靠断言 + 规格 + Kotlin 源码推导，复审时逐条回源核对 |
| 合成 fixture（按语法特征自造 HTML / JSON）与期望值 | 完成（100 条 10 文件，Codex 独立复审抽 43 条 clean） | Codex | `Tests/Conformance/fixtures/synthetic/` | 期望值按规格推导，需 Android 基线校正 |
| 阶段 0 收口：SUMMARY.md、DEVTREE 更新 | 完成（9b8874a56） | 主会话 | `docs/0-iOS适配规划/SUMMARY.md` | — |
| 规格 §3 补精确（5 处：编码、游标后置条件、splitRule 终点、引号范围、innerRule 失败） | 完成（603a5d508，371 行 105 引用） | Codex | `docs/spec/rule-engine.md` | — |
| **阶段 1 单元 2**：AnalyzeUrl 选项解析 + 一致性运行器（url-options 25 条） | 完成（1 轮复审 3 条全修；23 passed / 2 skipped） | Codex | `Packages/LegadoCore/Sources/LegadoCore/AnalyzeUrl/`、`Conformance/ConformanceRunner.swift` | 需 swift test 原始输出与用例明细 |
| **阶段 1 单元 3**：AnalyzeRule 词法 / ## 替换 / @get @put / 正则模式 / 合并，选择器引擎 protocol 化 | 完成（1 轮复审 6 条全修） | Codex |
| **阶段 1 单元 4**：SwiftSoup 实现 AnalyzeByJSoup（Default 私有语法 + CSS） | 完成（4d4ac0851；1 轮复审 3 条 P1 全修；HTML pretty-print 与 jsoup 逐字符对比未验证） | Codex |
| **阶段 1 单元 5**：JavaScriptCore JS 引擎（<js> / @js: / {{}}、注入变量、java 宿主一级离线子集） | 完成（1 轮复审 7 条全修；92 测试；JS 用例 19/19；已知差异见 `docs/spec/js-host-compat.md`） | Codex |
| **阶段 1 单元 6**：JSONPath 引擎（jayway 语义子集） | 完成（1 轮复审 4 条全修） | Codex |
| **阶段 1 单元 7**：XPath 引擎（Kanna / libxml2，对齐 JsoupXpath） | 完成（1 轮复审 5 条：3 修 + 2 记已知差异 `docs/spec/xpath-compat.md`） | Codex |
| **阶段 1 单元 8**：HtmlFormatter 排版（format 8 条黄金用例） | 完成（1 轮复审 1 条修） | Codex | `Packages/LegadoCore/Sources/LegadoCore/Format/` | 需 swift test 输出、8 条用例明细、正则方言差异 | `Packages/LegadoCore/Sources/LegadoCore/AnalyzeByXPath/` | 需 swift test 输出、xpath 用例明细、库差异清单 | `Packages/LegadoCore/Sources/LegadoCore/AnalyzeByJSonPath/` | 需 swift test 输出与 jsonpath 用例明细 | `Packages/LegadoCore/Sources/LegadoCore/JsEngine/` | 需 swift test 输出、JS 相关用例明细、三项兼容决策实验 | `Packages/LegadoCore/Sources/LegadoCore/AnalyzeByJSoup/` | 需 swift test 输出、用例明细、库差异清单 | `Packages/LegadoCore/Sources/LegadoCore/AnalyzeRule/` | 需 swift test 原始输出与 replace / template / prefix / regex / empty 用例明细 |
| **阶段 1 单元 1**：LegadoCore Package 骨架 + RuleAnalyzer（TDD） | 完成（2 轮复审 10 条全修，25 测试；第 3 轮修复留痕放行） | Codex | `Packages/LegadoCore/`（RuleAnalyzer 220 行、15 测试） | 报告附 swift test 全绿原始输出；沙箱需 `CLANG_MODULE_CACHE_PATH` 指向包内目录才能编译 |

## 3. 在途子 agent

| 任务 | 通道 | 任务书 / 输出 | session id | 派出时间 |
| --- | --- | --- | --- | --- |

已完成单元的实现会话（返修时 resume）：单元 8 `01a0967a-7e6c-7d52-b57b-91820d47ec19`、单元 7 `01a0966c-8be4-7970-9f8b-d0bd3561f68b`、单元 6 `01a09661-de70-78f2-8772-fb2e079c0241`、单元 5 `01a09648-cf95-7ec1-b3c0-a690f2e43fc8`、单元 1 `01a095c4-1477-7210-97da-da028d2b31a2`、单元 2 `01a095d3-a3b2-70f0-b4d1-3b7cf579abb5`、单元 3 `01a09623-b332-7eb2-9119-f97b21766dc8`、单元 4 `01a09632-de41-7a71-a0b3-3e19f9d23597`。

## 4. 下一步与未决

- **阶段 1 里程碑**：8 个单元全部提交，121 项 XCTest 0 失败，一致性用例 142/142 通过（8 条 UI 预览逻辑标 unsupported）。规则引擎在离线语料上已全覆盖；真实书源回归要等阶段 2 网络层。
- **下一步**：开阶段 2（轮次 1）：写 PROMPT / PLAN 待人类确认后再写代码——网络层（URLSession 按源选项）、java 宿主网络类方法（ajax / post / …）、BookSource 实体与 JSON 导入（含 Gson 宽松反序列化语义）、WebBook 搜索 / 目录 / 正文流程、GRDB schema。下个会话先实际起一次 `opus-explorer` 补 Opus 交叉复审。
- **决策**：XPath 仅 6.87%（279/4063）书源使用，阶段 1 接受 outerHtml→libxml2 桥接及其已知差异；「在 SwiftSoup DOM 上自研 XPath 求值器」列入后续 TODO，触发条件是真实书源回归暴露桥接损失。
- **未决**：labels 同步远端需人类同意。`ios` 分支已推送（origin/ios）。
- **经验**：长跑 Codex 任务用 `nohup … &` + `disown` 脱离 Bash 工具的后台任务生命周期，再用 until 循环等 `-o` 文件；直接 `run_in_background` 的长任务两次被 stopped。
