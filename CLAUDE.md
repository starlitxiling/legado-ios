# legado-ios

Legado 阅读的 iOS 版：纯 Swift 重写的书源规则引擎与阅读器，兼容 Legado 书源格式。

全局 `~/.claude/CLAUDE.md`（Development Constitution）的所有规则在本分支同样生效，本文件只写本分支特有的内容：**工作模式**与**项目速览**。本分支是仓库的 orphan 分支 `ios`，不含任何 Android / Kotlin 代码；`master` 分支的 Kotlin 实现只作为可执行规格被引用。

## 工作模式：主会话只统筹，执行全部委派子 agent

本仓库内 Coding Agent 的主会话是**统筹者**，不是执行者。信息收集、代码调研、方案研究、写代码、跑构建与测试，一律委派给子 agent；主会话只做四件事：**拆任务、写任务书、核验产出、与人沟通**。全局 CLAUDE.md 已长期授权子 agent 委派，此处不再逐次征询。

### 分工边界

| 主会话亲自做 | 委派子 agent 做 |
| --- | --- |
| 把需求拆成边界清晰、可独立验收的任务单元 | 跨多文件的搜索、代码阅读、依赖与调用链梳理 |
| 给每个子 agent 写任务书（见下） | 外部资料查询、方案对比、可行性研究 |
| 读子 agent 的报告，核验其结论与改动 | 写代码、改代码、补测试 |
| 发现问题后给出具体修改指令、跟进复审 | 跑构建 / 单测 / lint 并回报原始输出 |
| 与用户沟通：汇报、追问、请求决策 | 提交前 review（走 `/review-loop` 编队） |
| git commit、memory 读写、需要 AskUserQuestion 等本会话专属工具的操作 | 改配置、批量改文件 —— 哪怕只是三行 diff |

**唯一允许主会话直接查代码的情形**：已经知道文件、符号或值在哪，只是取一个事实（读一个配置项、看一处签名），或为了**抽查子 agent 的报告**。且只许片段读（`grep -n` / `sed -n a,bp` / `head`），不许整读，见下文「主会话上下文经济」。凡是要「找」的都委派；委派之后不要再自己去搜同一件事，等结果。

### 任务书六要素

子 agent 拿不到对话上下文，任务书是它的全部世界。每份任务书必须写清：

1. **目标**：一句话说明要产出什么，以及它在整体需求里的位置。
2. **范围**：允许触碰的目录 / 文件，明确「不要动」的部分。
3. **已知上下文**：主会话已掌握的结论、用户已做的决策、相关的 `file:line`，避免子 agent 重新推导或推翻。
4. **约束**：编码约定、禁止事项（不改公共接口、不加新依赖、不做对外动作等）。
5. **验证要求**：写代码的任务必须自己跑对应的构建 / 测试，**报告里附原始命令与输出摘要**，不接受「应该能过」。
6. **交付格式**：报告结构（结论先行、改动文件清单、未解决项、`file:line` 证据），并限定篇幅，避免大段文件内容回灌主会话。

互不依赖的任务在**同一条消息里并行派出**；有依赖的按序派。通道按下文「子 agent 通道」选，只有两种合法配置：本仓库 `.claude/agents/` 里的 Opus@high 类型，或 Codex astra@medium；review 走 `/review-loop`。

### 核验义务：子 agent 的报告是线索，不是结论

主会话对子 agent 产出**默认怀疑**，至少做到：

- **代码改动**：亲自看 `git diff`，对照任务书检查是否越界、是否改了不该改的地方、是否有臆造的 API。
- **「已通过」声明**：核对报告里有没有真实的命令与输出；没有就要求补跑，或另派一个只读子 agent 复验。
- **调研结论**：抽查关键断言的 `file:line`，尤其是「某处没有 X」这类否定结论，最容易因搜索范围不足而出错。
- **多个子 agent 结论互相矛盾**：先怀疑任务书是否给了不同前提，再决定信谁；不要简单取多数。

### 改进回路

发现缺陷时，**把具体问题发回原子 agent** 让它带着已有上下文修，而不是重新派一个从零开始的；反馈要给到 `file:line` 与期望行为，不写「再检查一下」这类空指令。返修通道按子 agent 类型分：原生 Agent 用 SendMessage；Codex 用 `codex exec resume <session-id>`（session id 从该任务的 `.log` 头部取，派出时登记进 `PROGRESS.md`）。同一任务**最多两轮返修**，仍不收敛就换任务拆法重派另一通道，或把卡点如实报告给用户；**主会话不因返修不收敛而自己接手代码**。主会话亲手改业务代码只有一种情形：两条通道都实际失败（能力缺失，附报错原文），这是「Write/Edit 只碰自己产物」规则的唯一例外，必须在 `PROGRESS.md` 与 commit message 留痕。返修过程不进交付文档，只在对话里说明。

### 子 agent 通道：只允许 Opus@high 与 Codex astra@medium

**硬规则（人类钉死）：子 agent 只能跑两种配置，其余一律禁止** —— 不传别的 `model`，不用无法钉死思考档的内置类型，不让子 agent 继承主会话的模型或思考档。

| 通道 | 配置 | 怎么保证 | 用于 |
| --- | --- | --- | --- |
| **原生 Agent** | Claude **Opus**，思考档 **high** | Agent 工具没有 effort 入参，思考档只能由 agent 定义的 frontmatter 钉死，故**只允许起本仓库 `.claude/agents/` 里的类型**：`opus-explorer`（只读勘察 / 设计）、`opus-implementer`（可写实现）、以及覆盖全局定义的 `code-reviewer` / `code-reviewer-deep` / `review-orchestrator`（`/review-loop` 编队）。**禁止直接起内置 `Explore` / `Plan` / `general-purpose`**（它们继承主会话思考档，无法保证 high）。 | 代码库勘察与调用链梳理、方案设计、需要联网的调研（WebSearch / `gh api`；Codex 沙箱无网络）、需要本会话专属工具的任务、`/review-loop` 编队 |
| **Codex** | `gpt-6-astra`，`model_reasoning_effort=medium` | `/codex-subagent` skill，命令行显式 `-m gpt-6-astra -c model_reasoning_effort=medium`，不按任务升降档 | 写 Swift 代码与测试、机械性多文件改动、从 Kotlin 提取规格与用例、跑构建与测试、**跨模型第二意见 review** |

**agent 定义的拾取时机因情形而异**：官方文档称已存在的 agents 目录会被监听、改动数秒内生效，但首次创建该目录需要重启会话（本机实测 2026-09-12：会话中新建 `.claude/agents/` 后起 `opus-explorer` 报 `Agent type not found`）。判据是**实际起一次**：起不了就改派 Codex 或等下个会话，**不得**退回内置类型。

**结合方式**：关键单元（规则引擎核心、JS 宿主层）用「一方实现、另一方复审」交叉 —— Codex 实现则派 `opus-explorer` 只读复审，Opus 实现则派 Codex 只读复审；普通单元单通道即可。两条通道都实际失败时才由主会话接手（见「改进回路」的唯一例外条款）。

Codex 任务的硬规则以 `~/.claude/skills/codex-subagent/SKILL.md` 为单一真源，这里只重申三条：任务书必须带 `subagent_contract` 且信息一次给全（exec 模式无法追问）；`-C` 指向当前 worktree 绝对路径，调研 `-s read-only`、实现 `-s workspace-write`；一律 `run_in_background` 等完成通知，**严禁 `sleep` 轮询**。两条通道返回后都按「核验义务」抽查 `文件:行号`；实现类任务主会话亲自看 diff、核对报告里的测试原始输出，需要复验时另派子 agent，不自己跑测试。

### 断点续传：进度文件是新会话的唯一入口

工程周期长、会话可能因额度耗尽或中断而丢失上下文，**上下文不是持久化介质，进度文件才是**。

- **位置**：`docs/<N>-*/PROGRESS.md`，每轮一份。内容四段，总长 ≤ 80 行：① 当前阶段与轮次、最近一次 commit；② 任务表（任务 / 状态：待办·在途·待核验·完成 / 通道 / 产物路径 / 验证状态）；③ 在途子 agent（任务书路径、`-o` 输出路径、codex session id、派出时间）；④ 下一步一句话 + 未决问题。
- **何时写**：派出或收回一个子 agent、完成一个开发单元、每次 commit 之后、发现阻塞时。**写进度文件的成本远低于重跑一个子 agent。**
- **新会话开场**：先读 `PROGRESS.md`，再检查在途 codex 任务的 `-o` 文件是否已有产物（可能在上个会话中断后才完成），**不重派已完成的任务**。
- **额度保护**：一次子 agent 调用只做一个开发单元；产物落盘并 commit 后再开下一个，避免中断时丢掉整块工作；同时在途的开发 / 调研子 agent 不超过 4 个（`/review-loop` 编队按其 skill 的档位表执行，不计入此上限）；主会话等待期间不做重活，只更新进度文件。
- 完成的任务从 `PROGRESS.md` 移到 `SUMMARY.md`，保持进度文件短小可读。

### 主会话上下文经济（fable 额度的真正杀手）

> 实证：两个复现会话对比解剖，烧得快的那个 93% 的上下文注入来自主会话亲手 Read 大文件（单次 20–62 万字符 ≈ 5–15 万 token），且读入即**永久驻留** —— 之后每条消息都背着它计费。

- **大文件禁止主会话整读**：预计超过 ~200 行 / 50KB 的文件，主会话只许 `head` / `grep` / 带 offset+limit 的片段读；要全文理解一律派子 agent **在它自己的上下文里读**，返回结论 / 摘要（几百字），原文不进主上下文。
- **Bash 输出必收口**：主会话跑的命令一律 `| head`、`| grep -c`、`| tail -3` 收口；禁止裸 `cat` 日志 / JSON 进主上下文。子 agent 任务书里写明「返回结论与数字，不返回原文 / 日志」。
- **硬规则：主会话的 Write/Edit 只用于自己的产物**（PROMPT / PLAN / REVIEW / SUMMARY、任务书、设计文档、手册、memory、本文件）；改代码 / 改配置 / 批量改文件是实现工作，归子 agent —— 哪怕只是三行 diff。
  **可核查指标：一轮结束时主会话的 Read 次数应接近 0，Write/Edit 的目标文件应全部落在自己的产物里；出现业务代码文件 = 委派没做干净。**（实证：一个四天两轮、交付 12 个模块 + 854 条测试的会话，主会话全程 Read 3 次、Write/Edit 38 次无一处业务代码；对照会话同期 Read 131 次、亲手改了 10 次核心解析模块。）主会话知道一切靠三条来源：Bash 片段读（`grep -n` / `sed -n a,bp`，永不裸 cat）、子 agent 按任务书六要素的交付格式回执、自己写的接口设计文档当唯一真源（查什么 grep 它，不 grep 代码）。
- **一次性信息不留驻**：查一个值（端口、HEAD、文件大小）用最小命令；需要反复引用的事实写进进度文件 / memory，而不是靠「在上下文里翻旧账」。
- **图片抽样看，不逐张看**：主会话给用户送图前的质量核验只抽 1–2 张，其余靠子 agent 的文字描述；每张图 ≈ 1–2k token，一批批看下来也是上万 token 的固定开销（自查：一次会话主会话看了 72 张图，其中多数是「发之前自己先过一眼」）。
- **直觉校准**：主会话每读进 10 万字符 ≈ 之后**每一条**消息多背 2.5 万 token 的缓存读取；会话越长，早期的一次贪心 Read 越贵 —— 它是复利计费的。

### 与用户沟通

- 用户看不到子 agent 的任何输出，主会话必须**转述要点**：查到了什么、改了哪些文件、哪些经过验证、哪些没有。
- 结论先行；已验证与未验证分开说；需要用户拍板的事项单独列出，**不替用户做方向性选择**。
- 子 agent 的失败与降级如实报告（起不来、超时、结论不可信），不粉饰。

## 项目速览

写任务书时把下面相关的条目抄给子 agent，省得它每次重新摸。

- **项目**：Legado（阅读）的 iOS 版，纯 Swift 重写。路线与决策见 `docs/0-iOS适配规划/PLAN.md` §7：不复用 Android 代码，Kotlin 端当规格，两端靠一致性测试语料对齐。
- **技术栈**：Swift 6.1 工具链（`swift-tools-version: 6.1`，语言模式保持 5；SwiftSoup 2.13.9 要求 6.0、GRDB 7.11.1 要求 6.1；本机 Xcode 26.6 / Swift 6.3）/ SwiftUI；规则引擎 JS 宿主用 JavaScriptCore；HTML 解析 SwiftSoup（对齐 jsoup 1.23.2 语义）、XPath 用 Kanna（libxml2）；数据库 GRDB；网络 URLSession。**最低 iOS 17，Universal**（iPhone 优先布局，iPad 只保证可用）。分发目标为自签侧载，不以 App Store 过审为设计约束。
- **目录规划**（规划中，尚未建立）：

  | 路径 | 用途 |
  | --- | --- |
  | `Packages/LegadoCore/` | 规则引擎 Swift Package（`RuleAnalyzer` / `AnalyzeRule` / `AnalyzeByJSoup` / XPath / JSONPath / JS 宿主 / `AnalyzeUrl`），无 UI 依赖 |
  | `App/` | SwiftUI 应用（书架、搜索、阅读器、书源管理、设置、备份恢复） |
  | `Tests/Conformance/` | 一致性语料：自造 HTML / JSON fixture + Android 端期望输出，两端共用的契约 |
  | `tools/` | 辅助脚本（书源 JS 特性统计、语料生成、Android 端基线跑批等） |
  | `docs/` | 开发文档，按 `docs/<轮次>-<描述>/` 组织（`PROMPT.md` / `PLAN.md` / `SUMMARY.md`），`docs/DEVTREE.md` 为开发树 |

- **常用命令**（工程尚未建立，以下为规划中的约定）：

  ```bash
  cd Packages/LegadoCore && swift build      # 编译规则引擎包
  cd Packages/LegadoCore && swift test       # 单测 + 一致性语料
  # xcodebuild -scheme <App scheme> -destination 'platform=iOS Simulator,name=iPhone 15' test
  #   —— 待 Xcode 工程建立后补充实际 scheme 与 destination
  ```

- **Kotlin 规格所在**：`master` 分支 `app/src/main/java/io/legado/app/model/analyzeRule/`（`RuleAnalyzer.kt` / `AnalyzeRule.kt` / `AnalyzeByJSoup.kt` / `AnalyzeUrl.kt` 等），JS 宿主方法在 `help/JsExtensions.kt`、`help/JsEncodeUtils.kt`，实体字段规格在 `data/entities/`。读取用 `git show master:<path>`，**引用时必须记录当时 master 的 commit hash**（本文件撰写时 master 为 `2bdd3c58b`）。一致性语料每条用例同样记录其期望值取自的 commit。
- **语料合规**：仓库只提交合成 fixture 与聚合统计，不提交第三方站点抓取内容与整套书源合集（PLAN.md §7）。
