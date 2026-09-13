# 进度（阶段 4 · 功能对齐，轮次 3）

> 新会话先读本文件。最后更新：2026-09-14 04:45（本机时钟）。

## 1. 当前位置

- 起点 `55240af68`（阶段 3 收口）。环境：iOS 26.5 平台组件已装，模拟器 `Legado-Test`（11D3CFAE-B0CC-4C01-A767-34D43B3DB5AF），XcodeGen 2.46.0。
- 批次 1：B1 / B2 / B3 并行。**事故**：三任务在 2026-09-14 00:01 因磁盘满（Codex 隔离副本 + 8.5 GB 平台组件 + 他项目 18 GB uv 缓存 `/tmp/prometheus25-uv-cache`）崩溃；清理可重建产物后以 resume 续跑，并禁止再在 /tmp 做隔离副本。

## 2. 任务表

| 单元 | 状态 | 产物 | 验证 |
| --- | --- | --- | --- |
| B1 发现页 + 封面 + 图片正文 | 完成（1 轮复审 4 条全修） | `Features/Explore`、`Shared/RemoteImage`、`LegadoCore/Explore`、`Images` | 离线测试 + 主会话 xcodebuild |
| B2 登录 + Cookie + 校验 | 完成（1 轮复审 10 条全修） | `Features/SourceLogin`、`Features/CheckSource`、LegadoCore `Login/`、`CheckSource/` | 离线测试 |
| B3 本地书 TXT / EPUB | 完成（1 轮复审 6 条全修） | LegadoCore `LocalBook/`、`Features/LocalImport` | 离线测试 |
| B4 WebView 抓取 | 在途 | LegadoCore `WebView/`、App `Shared/HeadlessWebView` | 离线测试 |
| B5 纯 JS 书源 | 在途 | LegadoCore `JsSource/` | 离线测试 |
| B6 听书 TTS | 在途 | App `Features/ReadAloud`、LegadoCore `TTS/` | 离线测试 |
| B7 本地书 MOBI / PDF | 在途 | LegadoCore `LocalBook/{Mobi,Pdf}` | 离线测试 |
| B8–B15 | 待办 | 见 PLAN | — |

## 3. 在途子 agent

| 任务 | 通道 | 输出 | session id | 派出时间 |
| --- | --- | --- | --- | --- |
| B1 实现会话（返修时 resume） | — | — | `01a09b74-f5a7-7f02-b1e3-cdc7232de023` | — |
| B2 实现会话（返修时 resume） | — | — | `01a09b74-f5a7-7933-bc9b-219b4a42829e` | — |
| B3 实现会话（返修时 resume） | — | — | `01a09b74-f5a7-7a32-bc80-133de4717b46` | — |

## 4. 下一步与未决

- 批次 1 已合并：xcodebuild 通过，LegadoCore 327 + appcore-check 99 项 0 失败。批次 2（B4–B7）并行中。
