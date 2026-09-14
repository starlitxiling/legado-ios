# 交接文档：Legado iOS 适配（给下一台机器上接手的 Coding Agent）

> 写于 2026-09-14。目的：让另一台电脑上的 Claude（fable）不依赖原机器的任何本地状态，直接接手。**先通读本文，再读 `docs/3-阶段4功能对齐/PROGRESS.md`。**

## 1. 一句话现状

Android 阅读器 Legado 的 iOS 纯 Swift 重写已完成规划 → 引擎 → 数据网络 → MVP 界面 → **全部功能对齐**四个阶段，代码全部在本仓库 orphan 分支 `ios`（以 `origin/ios` 的最新提交为准）。合并态验证：LegadoCore 539 项、appcore-check 232 项、icon-render 7 项测试 0 失败，`xcodebuild`（iOS 真机目标）构建通过，未签名安装包可由 `tools/build-ipa.sh` 产出。**尚未做任何真机 / 模拟器交互验证**（人类指示「先都做了，不急真机测试」）。

## 2. 分支与目录形态

| 分支 | 内容 | 状态 |
| --- | --- | --- |
| `master` | 上游 Android 代码（Kotlin，作为**可执行规格**）+ 项目级 `CLAUDE.md`（工作模式）+ `.claude/agents/` 五个 Opus@high 定义 + `docs/0-iOS适配规划/` | 已推送 |
| `ios` | orphan 分支，全部 iOS 代码与文档 | 已推送 |

**历史已被重写过一次**（2026-09-14）：本工程此前 35 个提交的作者是一个错误的公司身份，已用 `git filter-branch` 统一改成 `starlitxiling <1754165401@qq.com>`，范围只限我们自己的提交（`master` 上 5 个 + `ios` 全部 30 个），上游 Legado 作者的 8444 个提交及其 hash 原样未动，与上游的共同历史仍在，将来照常能 fetch 上游更新。远端两个分支都已 force push。**因此：任何早于该时点的本地 clone 都与远端分叉了，直接重新 clone，不要 merge 或 rebase 旧副本。** 旧历史的备份 tag（`backup/master-*`、`backup/ios-*`）只存在于原机器本地，未推送。文档里引用的提交 hash 已同步更新为重写后的值。

原机器用 worktree 布局：主 checkout 在 `master`，`ios` 分支 checkout 在 `.claude/worktrees/ios/`（该目录被 `.claude/.gitignore` 忽略）。新机器推荐同样布局：

```bash
git clone <origin> legado-ios && cd legado-ios          # master
git worktree add .claude/worktrees/ios ios               # ios 分支
```

Kotlin 规格固定按 commit `2bdd3c58b` 读（所有复审与返修的行号引用都指它）；路径前缀 `app/src/main/java/io/legado/app/`。`ios` 分支上任何任务书里出现的绝对路径 `/Users/wujie/Work/legado-ios/...` 都要换成新机器的路径。

## 3. 环境准备（新机器）

- macOS + Xcode（原机 26.5，含 iOS 26.5 平台组件；`xcodebuild -downloadPlatform iOS` 约 8.5 GB，磁盘至少留 20 GB）。
- Swift 工具链 6.1（`Package.swift` tools-version 6.1，语言模式 5）。
- XcodeGen（原机 2.46.0）：`App/project.yml` 是工程真源，生成物 `App/Legado.xcodeproj` 与 `App/Info.plist` 也提交，改 `project.yml` 后必须 `cd App && xcodegen generate` 并把生成物一起提交。
- Codex CLI（OpenAI）：`codex exec -m gpt-6-astra -c model_reasoning_effort=medium`。
- `.env.local`（gitignored，**不在仓库里**）：WebDAV 测试凭据，格式见 `.env.example`；向人类要，只读使用。
- 书源语料：仓库只提交合成 fixture 与聚合统计；真实书源合集与备份包在原机 scratchpad，**不随仓库走**。需要时按 `docs/0-iOS适配规划/宿主API优先级.md` 顶部记录的来源仓库重新拉取，或向人类要。

首次进入 `ios` 分支后：

```bash
# 依赖 resolve（Codex 沙箱无网络，只能主会话跑）
swift package --package-path Packages/LegadoCore --cache-path .build/cache --config-path .build/config --security-path .build/security resolve
swift package --package-path tools/appcore-check --cache-path .build/cache --config-path .build/config --security-path .build/security resolve
mkdir -p .build/tmp .build/clang-cache
```

常用命令（都在 `ios` 分支根目录）：

```bash
# 单元测试（LegadoCore / appcore-check / icon-render 三个包，把 --package-path 换掉即可）
CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/clang-cache" TMPDIR="$PWD/.build/tmp" \
  swift test --package-path Packages/LegadoCore --cache-path "$PWD/.build/cache" --disable-sandbox --disable-automatic-resolution --skip-update
# iOS 构建（只有主会话能跑，Codex 沙箱写不了 ~/Library）
CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache" xcodebuild -project App/Legado.xcodeproj -scheme Legado \
  -destination 'generic/platform=iOS' -configuration Debug -derivedDataPath .build/DerivedData \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
# 未签名 ipa → dist/Legado-1.0-<hash>.ipa
bash tools/build-ipa.sh
```

`tools/appcore-check` 是给 App 侧非 UI 逻辑做测试的 SwiftPM 包，通过**软链**引用 `App/Sources` 下不 import UIKit / SwiftUI 的文件；新增 App 逻辑要在 `tools/appcore-check/Package.swift` 追加目标。

## 4. 合作方式（原样沿用，已在 `master` 的 `CLAUDE.md` 固化）

**主会话只统筹**：拆任务、写任务书、核验产出、与人沟通、git commit、进度文件与 memory。写代码、跑测试、读大文件、搜代码一律委派子 agent。主会话的 Read 应接近 0，Write/Edit 只碰自己的产物（任务书、PLAN / SUMMARY / PROGRESS / HANDOFF、spec 文档）。

**子 agent 只有两种合法配置**（人类钉死）：
- 原生 Agent：仅限仓库 `.claude/agents/` 里的 Opus@high 类型（`opus-explorer` / `opus-implementer` / `code-reviewer` / `code-reviewer-deep` / `review-orchestrator`）。原机会话里项目级定义**没有加载**（起 `opus-explorer` 报 `Agent type not found`），所以整个工程都是 Codex 做的。**新机器开场先实际起一次 `opus-explorer`**；能起就把「Opus 交叉复审」补上。
- Codex：`codex exec -C <worktree 绝对路径> -s workspace-write|read-only -m gpt-6-astra -c model_reasoning_effort=medium --skip-git-repo-check -o <产物.md> "<任务书全文>"`。

**每个开发单元的固定流程**（阶段 4 共 17 个单元全部如此）：
1. 主会话写任务书（模板见 `docs/tasks-archive/`，每份都带 `<subagent_contract>` + 目标 / 工作目录与已有能力 / Kotlin 规格文件 / 产出 / 测试要求；`_subagent_contract.md` 是通用契约）。
2. Codex 实现，TDD 先红后绿，报告附命令与末尾 10 行。
3. 另起一个 Codex **只读、新会话**复审（`review-*.prompt.md`），对照 Kotlin 逐条给 `Swift 文件:行号` + `Kotlin 文件:行号` + P 级。
4. 主会话把 finding 用 `codex exec resume --skip-git-repo-check -o <产物> <session-id> "<逐条指令>"` 发回**原实现会话**返修（resume 不接受 `-C` / `-m` / `-s`；session id 在该任务 `.log` 头部 `session id: …`，派出时登记进 PROGRESS）。同一任务最多两轮返修，不收敛就换拆法或报告人类。
5. 批次收口：一个 Codex 跑合并态两套全量（只允许修测试间干扰，业务失败原样报告）→ 主会话 `xcodegen` + `xcodebuild` → 编译错误发回对应单元 → 提交推送 → 更新 PROGRESS / SUMMARY / memory。
6. 并行上限：同时在途的开发 / 复审子 agent 不超过 4 个。

**核验义务**：子 agent 报告是线索不是结论。看 `git status` 确认没越界改别的目录；报告里必须有真实的「Executed N tests, with M failures」原文；复审 finding 抽查 `文件:行号`。Codex 写在 `docs/` 下的过程留痕文档（`B13-备份与设置.md`、`Bx-复审验证.md` 之类）一律删掉，不进交付文档；有用的决策内容合并进 SUMMARY。

**一律以 Kotlin 为准**：主会话凭印象写进任务书的规格多次出错（书源类型常量、偏好备份格式、备份文件名、默认规则集、RSS 主键、webDavBookAutoRestore 语义），Codex 每次都按「关键假设失效则停机」的约定停下来问。遇到这种停机，回源核对后给出决策再 resume，不要坚持任务书。

**断点续传**：`docs/<N>-*/PROGRESS.md` 是唯一真源（≤ 80 行：阶段与最近 commit / 任务表 / 在途子 agent 含产物路径与 session id / 下一步）。派出或收回子 agent、每次 commit 后都更新。新会话开场先读它，再检查在途任务的 `-o` 产物是否已落盘，不重派已完成的任务。

## 5. 原机器踩过的坑（新机器大概率会再遇到）

- **Bash 后台任务会被会话生命周期回收**（状态显示 stopped / killed）。长跑任务一律 `nohup … < /dev/null > x.log 2>&1 & disown`，然后用 `until [ -s 产物 ]; do sleep 10; done` 的**前台**循环等（超过 10 分钟会被移到后台，再挂一次即可）。
- **zsh 不对 `$VAR` 分词**：`for f in $LIST` 只会迭代一次，等待循环因此漏检了四份已落盘的产物。列表写字面量，或用数组。
- **Codex 沙箱**：无网络（依赖 resolve 由主会话做）、写不了 `~/Library`（xcodebuild 只能主会话跑）、只读模式下跑不了 `swift test`（要写构建缓存）。多个 Codex 并行跑同一包的测试会在 `.build` 锁上串行等待，看起来像卡住。
- **磁盘**：原机多次撑满（Codex 在 /tmp 做隔离副本、iOS 平台组件、别的项目缓存）。任务书里写死「不在 /tmp 做隔离副本」；可随时删的：`.build/DerivedData`（0.8 GB）、`Packages/LegadoCore/.build`（1.5 GB）、`tools/*/.build`；删了 DerivedData 下次 xcodebuild 全量重建约 10 分钟。
- **git add 中文路径**：用 `git -c core.quotepath=false status --short | awk '{print $2}' | tr '\n' '\0' | xargs -0 git add --`，否则引号转义的路径会漏掉。
- **macOS-only API**：Codex 在 macOS 上编译通过不代表 iOS 能编（出现过 `CocoaError.Code.validationMissingMandatoryProperty`、`WKHTTPCookieStore.getAllCookies()`、主 actor 隔离）；每批次必须由主会话跑 iOS 目标的 `xcodebuild`，错误原文发回对应单元。
- **同名类型冲突**：并行单元各自新建同名 View（`TxtTocRulesView`）在 App target 里冲突，以新单元为准、删旧私有实现。
- **flaky 测试要当业务 bug 查**：HttpTTS 缓存键散列了未排序 JSON，单跑也 45% 失败，根因不是测试干扰。

## 6. 已完成（细节见各轮 SUMMARY）

| 轮次 | 文档 | 内容 |
| --- | --- | --- |
| 0 | `docs/0-iOS适配规划/` | 路线决策（纯 Swift 重写 + 一致性测试集、自签侧载、iOS 17 Universal、orphan 分支）、规则引擎规格、黄金 / 合成用例、语料统计 |
| 1 | `docs/1-阶段2数据与网络/` | 阶段 1 引擎 8 单元 + 阶段 2 网络 / 实体 / WebBook / GRDB / 备份 6 单元 |
| 2 | `docs/2-阶段3-MVP界面/` | SwiftUI MVP 6 单元，首次可构建 ipa |
| 3 | `docs/3-阶段4功能对齐/` | B1–B17：发现 / 登录 / 本地书四种格式 / WebView / 纯 JS 书源 / TTS / 书源编辑与调试 / 阅读器进阶 / 书架与下载 / RSS / 漫画音频 / 备份上传 / 设置全集 / 局域网 Web + WebSocket / 实体补齐 / 备用图标 |

已知差异与「未验证」清单：`docs/spec/{rule-engine,js-host-compat,xpath-compat,network-compat,storage-notes,backup-notes,entities-compat,settings-compat}.md`。

## 7. 后面要做（按优先级）

1. **真机 / 模拟器冒烟**（等人类决定时机；人类有自签能力）。建议顺序：安装 ipa → 导入书源（人类的 WebDAV 备份或书源 JSON）→ 搜索 / 详情 / 目录 / 正文 → 本地书四种格式 → 听书与音频书后台播放、锁屏控制 → 漫画 → RSS → 备份上传到 WebDAV（此时才允许真实 PUT，且用测试账号）→ 局域网 Web 服务用浏览器访问 → 设置各页。每个失败点开一个单元按 §4 流程修，回填对应 `docs/spec/*-compat.md`。
2. **Opus 交叉复审**：新机器先起 `opus-explorer` 确认可用，对规则引擎核心（`Packages/LegadoCore/Sources/LegadoCore/{RuleAnalyzer,AnalyzeRule,AnalyzeByJSoup,AnalyzeByJSonPath,AnalyzeByXPath}`）与 JS 宿主层（`JsEngine/`）做只读复审，finding 发 Codex 返修。
3. 只存偏好未生效的两项：`customHosts` 接入网络层 DNS / hosts 映射；`localPassword` 备份 zip 加密（现有 zip 写入器是 store 模式无加密）。
4. 书源类型 3（文件下载）与 4（视频）目前只有占位提示。
5. 真实书源回归：阶段 2 挑的 8 个候选书源只有 1 个端到端通过；XPath 桥接（Kanna）与 jsoup 的祖先关系 / table 补全差异按使用率接受，自研 XPath 求值器列为触发式 TODO。
6. HTML pretty-print 与 jsoup 逐字符一致性未验证。

## 8. 原机器上不随仓库走的东西

- memory（`~/.claude/projects/<项目>/memory/`）：两条——「进度入口：新会话先读 ios 分支 `docs/<N>-*/PROGRESS.md`，决策见轮次 0 PLAN §7」「子 agent 只允许 Opus@high 或 Codex astra@medium，每步更新 PROGRESS 防中断白烧」。新机器按本文重建即可。
- `/tmp/codex-sub/`：全部任务书已归档到 `docs/tasks-archive/`；Codex 的 session 在原机 `~/.codex/sessions`，新机器**不能 resume 旧会话**，遗留问题只能新开任务书。
- scratchpad 里的真实书源合集、真实备份包、8 份冒烟书源：不进仓库，见 §3。
- `dist/*.ipa`：gitignored，新机器自己打。
