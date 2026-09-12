# 进度（阶段 0 · 立项与规格化）

> 新会话先读本文件。最后更新：2026-09-12 22:40。

## 1. 当前位置

- 阶段 0，轮次 0。分支 `ios`（orphan，worktree `.claude/worktrees/ios`），**尚无任何 commit**；master 最新 `35a485ed3`（规则 + `.claude/agents/` 已提交）。
- 分发 / 路线 / 范围决策已全部拍板，见 `PLAN.md` §7。
- 子 agent 硬规则：只允许 Opus@high（仓库 `.claude/agents/` 定义，**下个会话才生效**）或 Codex `gpt-6-astra` @ medium；本会话只能用 Codex。规则见 `CLAUDE.md`「子 agent 通道」。
- 2026-09-12 16:10 左右四个原生子 agent（两路 review、黄金用例、语料统计）因额度 429 中断，产物作废，改派 Codex 重做。

## 2. 任务表

| 任务 | 状态 | 通道 | 产物 | 验证 |
| --- | --- | --- | --- | --- |
| 项目骨架（README / CLAUDE / DEVTREE / labels / gitignore） | 待核验 → 待 commit | 原生 general-purpose | 根目录 16 文件 | 主会话已抽查结构与 area 标签 |
| 规则引擎语言无关规格 | 待 commit | 原生 general-purpose + Codex 修正 | `docs/spec/rule-engine.md`（368 行，96 处源码引用） | Codex 跨模型审出 6 处与源码不符已修并复审通过；主会话核实 3 条 |
| Kotlin 测试 → 黄金用例 JSON | 待 commit | Codex | `Tests/Conformance/fixtures/golden/`（6 文件 42 条） | Codex 复审抽 6 条 + 主会话抽 1 条，期望值逐字一致 |
| 公开书源语料频率统计 + 宿主 API 优先级表 | 待办（主会话先下载合集到 scratchpad，再派 Codex 写脚本统计） | 主会话下载 + Codex | `tools/corpus/analyze_sources.py`、`docs/0-iOS适配规划/宿主API优先级.md` | 待抽查统计口径 |
| Android 基线运行环境（JDK 21 + Android SDK） | 暂按「不装」推进，人类可随时改 | — | — | 本机无 JDK / SDK；期望值靠已有断言 + 规格推导，标「未经 Android 实测」 |
| 合成 fixture（按语法特征自造 HTML / JSON）与期望值 | 在途 | Codex | `Tests/Conformance/fixtures/synthetic/` | 期望值按规格推导，需 Android 基线校正 |
| 阶段 0 收口：SUMMARY.md、DEVTREE 更新 | 待办 | 主会话 | `docs/0-iOS适配规划/SUMMARY.md` | — |

## 3. 在途子 agent

| 任务 | 通道 | 任务书 / 输出 | session id | 派出时间 |
| --- | --- | --- | --- | --- |
| 语料统计 | Codex workspace-write | `/tmp/codex-sub/corpus-stats.prompt.md` → `/tmp/codex-sub/corpus-stats.md`；合集在 scratchpad `corpus/`（8 文件 + manifest.tsv，共 9776 条，按 bookSourceUrl 去重 4063 源） | `01a095b1-1e88-7150-b392-8fd36effa1df` | 2026-09-12 21:20 |
| 语料统计 r2（词表扩到 AnalyzeRule / AnalyzeUrl / BaseSource、URL 选项解析修正） | Codex resume | `/tmp/codex-sub/corpus-stats-r2.md` | 同上 | 2026-09-12 22:30 |
| 合成 fixture（按规格推导，标未经 Android 实测） | Codex workspace-write | `/tmp/codex-sub/synthetic-fixtures.prompt.md` → `/tmp/codex-sub/synthetic-fixtures.md`，写 `Tests/Conformance/fixtures/synthetic/` | `01a095bf-3128-7e52-86c5-56dda2ddc100` | 2026-09-12 22:35 |

已收回：Codex review master 规则（3 条，已改 CLAUDE.md）；Codex review ios 首批（8 条：6 条规格→spec-fix-r1，1 条 CLAUDE.md 已改，1 条 `.gitignore` 待 Package 建立时按目录加）。

## 4. 下一步与未决

- **下一步**：三个 Codex 任务回收并抽查后，派一次收窄的 Codex 复审（两份 CLAUDE.md 修正 + 规格修正 + 黄金用例 + 统计），通过即在 master 提交规则改动、在 `ios` 分支做首个 commit；随后派「合成 fixture」任务。
- **未决**：① Android 基线环境是否安装（见任务表）；② `ios` 分支推送到远端需人类同意；③ labels 同步远端需人类同意。
