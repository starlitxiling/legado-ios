# 进度（阶段 4 · 功能对齐，轮次 3）

> 新会话先读本文件。最后更新：2026-09-14 09:40（本机时钟）。

## 1. 当前位置

- 起点 `55240af68`（阶段 3 收口）。环境：iOS 26.5 平台组件已装，模拟器 `Legado-Test`（11D3CFAE-B0CC-4C01-A767-34D43B3DB5AF），XcodeGen 2.46.0。
- 批次 1：B1 / B2 / B3 并行。**事故**：三任务在 2026-09-14 00:01 因磁盘满（Codex 隔离副本 + 8.5 GB 平台组件 + 他项目 18 GB uv 缓存 `/tmp/prometheus25-uv-cache`）崩溃；清理可重建产物后以 resume 续跑，并禁止再在 /tmp 做隔离副本。

## 2. 任务表

| 单元 | 状态 | 产物 | 验证 |
| --- | --- | --- | --- |
| B1 发现页 + 封面 + 图片正文 | 完成（1 轮复审 4 条全修） | `Features/Explore`、`Shared/RemoteImage`、`LegadoCore/Explore`、`Images` | 离线测试 + 主会话 xcodebuild |
| B2 登录 + Cookie + 校验 | 完成（1 轮复审 10 条全修） | `Features/SourceLogin`、`Features/CheckSource`、LegadoCore `Login/`、`CheckSource/` | 离线测试 |
| B3 本地书 TXT / EPUB | 完成（1 轮复审 6 条全修） | LegadoCore `LocalBook/`、`Features/LocalImport` | 离线测试 |
| B4 WebView 抓取 / 浏览器 | 完成（`b603da0c2`；复审 3 条已修） | LegadoCore `WebView/`、App `Shared/HeadlessWebView`、`Features/Browser` | 离线测试 |
| B5 纯 JS 书源 | 完成（`b603da0c2`；复审 4 条已修） | LegadoCore `JsSource/` | 离线测试 |
| B6 听书 TTS | 完成（`b603da0c2`；复审 9 条已修 + UIBackgroundModes audio） | App `Features/ReadAloud`、LegadoCore `TTS/` | 离线测试 |
| B7 本地书 MOBI / PDF | 完成（`b603da0c2`；复审 4 条已修） | LegadoCore `LocalBook/{Mobi,Pdf}` | 离线测试 |
| B8 书源编辑进阶 | 待核验 r2（5 条已修：26 条 TXT 默认规则恢复 + 5 条默认字典移植、导入 id 预留、JSON 数组、发现启停、v4 只填空表；App 150 全过；Core 408 中 1 失败：B6 `ReadAloudTests.testHttpRuleAndCache` unmatched GET tts.test/hello/5，B9 同期全过，疑与 B10 在途改动相关，收口任务诊断） | LegadoCore `Debug/ Export/`、App `Features/Sources/{Edit,Debug}` 等 | 离线测试 |
| B9 阅读器进阶 | 待核验 r2（5 条已修：连续滚动、章末预取、段评小数、自动阅读逐步揭示、滑动动画；App 150 + Core 408 全量通过） | LegadoCore `Reader/`、App `Features/Reader/*` | 离线测试 |
| B10 书架进阶与下载 | 待核验 r2（6 条已修：图片补下载与完整判定、EPUB 图片入包、仅更新已读条件、目录替换 sync 定位、lastCheckCount 只增、封面失败继续；Core 411 + App 157 全量通过） | LegadoCore `Cache/`、App `Features/{Bookshelf,Download,BookDetail/Edit}` | 离线测试 |
| B11–B15 | 待办（批次 4） | 见 PLAN | — |

## 3. 在途子 agent

| 任务 | 通道 | 输出 | session id | 派出时间 |
| --- | --- | --- | --- | --- |
| B6 r3：TTS `testHttpRuleAndCache` 单跑也间歇失败（unmatched 第二次 GET），定位竞态 | Codex resume（nohup） | `/tmp/codex-sub/s4-b6-tts-r3.md` | `01a09c00-f589-7562-8954-d1d6aaabc77d` | 2026-09-14 09:40 |
| 批次 3 xcodebuild | 主会话 nohup | `.build/xcodebuild-batch3.full.log` | — | 2026-09-14 09:40 |
| B8 实现会话（返修时 resume） | — | — | `01a09c2d-13ba-79a3-bd27-29e24d9fb0db` | 2026-09-14 07:40 |
| B9 实现会话（返修时 resume） | — | — | `01a09c2d-1333-7271-b4a1-bab9c64cc1ec` | 2026-09-14 07:40 |
| B10 实现会话（返修时 resume） | — | — | `01a09c2d-13e5-7bb2-9b01-8d0eadb04f35` | 2026-09-14 07:40 |

批次 1 实现会话（返修时 resume）：B1 `01a09b74-f5a7-7f02-b1e3-cdc7232de023`、B2 `01a09b74-f5a7-7933-bc9b-219b4a42829e`、B3 `01a09b74-f5a7-7a32-bc80-133de4717b46`。批次 1 提交 `1480ad923`。

## 4. 下一步与未决

- 批次 1、2 已合并推送（`b603da0c2`）。批次 3（B8–B10）三单元返修完毕，收口：project.yml 已加 BGTaskSchedulerPermittedIdentifiers + fetch；合并态 Core 411 / App 157 通过，但 B6 的 TTS 缓存用例间歇失败（单跑也失败），修好并 xcodebuild 通过后提交推送；批次 4 任务书已备好 `/tmp/codex-sub/s4-b{11-rss,12-media,13-backup-settings,14-webserver,15-entities}.prompt.md`（B11–B14 并行，B15 最后）。
