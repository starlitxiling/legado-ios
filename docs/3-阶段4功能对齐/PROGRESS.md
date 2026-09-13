# 进度（阶段 4 · 功能对齐，轮次 3）

> 新会话先读本文件。最后更新：2026-09-14 07:15（本机时钟）。

## 1. 当前位置

- 起点 `55240af68`（阶段 3 收口）。环境：iOS 26.5 平台组件已装，模拟器 `Legado-Test`（11D3CFAE-B0CC-4C01-A767-34D43B3DB5AF），XcodeGen 2.46.0。
- 批次 1：B1 / B2 / B3 并行。**事故**：三任务在 2026-09-14 00:01 因磁盘满（Codex 隔离副本 + 8.5 GB 平台组件 + 他项目 18 GB uv 缓存 `/tmp/prometheus25-uv-cache`）崩溃；清理可重建产物后以 resume 续跑，并禁止再在 /tmp 做隔离副本。

## 2. 任务表

| 单元 | 状态 | 产物 | 验证 |
| --- | --- | --- | --- |
| B1 发现页 + 封面 + 图片正文 | 完成（1 轮复审 4 条全修） | `Features/Explore`、`Shared/RemoteImage`、`LegadoCore/Explore`、`Images` | 离线测试 + 主会话 xcodebuild |
| B2 登录 + Cookie + 校验 | 完成（1 轮复审 10 条全修） | `Features/SourceLogin`、`Features/CheckSource`、LegadoCore `Login/`、`CheckSource/` | 离线测试 |
| B3 本地书 TXT / EPUB | 完成（1 轮复审 6 条全修） | LegadoCore `LocalBook/`、`Features/LocalImport` | 离线测试 |
| B4 WebView 抓取 / 浏览器 | 待核验 r2（3 条已修：Cookie 经持久化事务合并并同步内存、浏览器 URL 正则整体锚定、UA 宿主注入真实 WebKit UA；定向 15 项通过；全量待合并态） | LegadoCore `WebView/`、App `Shared/HeadlessWebView`、`Features/Browser` | 离线测试 |
| B5 纯 JS 书源 | 待核验 r2（4 条已修：登录脚本优先 mainJs、config 先归一化、BaseSource 29 方法两客户端齐全、变量空间；filter 37 + appcore 12 通过；全量 3 失败在 HeadlessWebView 属 B4 在途） | LegadoCore `JsSource/` | 离线测试 |
| B6 听书 TTS | 待核验 r2（9 条已修：暂停期失败态、HttpTTS 复用 SourceScriptBridge、段内起点、跨页推进/按页模式、定时只计有效播放、中断恢复、坏缓存驱逐+重合成 2 次、预合成整轮取消、缓存 128MiB/10min；核心 20 + App 12 + 全量 388 通过） | App `Features/ReadAloud`、LegadoCore `TTS/` | 离线测试 |
| B7 本地书 MOBI / PDF | 待核验 r2（4 条已修：PDF 每 10 页一章、NCX 父子保留 isVolume、解析器按路径+mtime 缓存按记录解压、KF7 pagebreak 区段映射；核心 26 + App 20 通过；全量 1 失败为 B6 在途朗读测试） | LegadoCore `LocalBook/{Mobi,Pdf}` | 离线测试 |
| B8–B15 | 待办 | 见 PLAN | — |

## 3. 在途子 agent

| 任务 | 通道 | 输出 | session id | 派出时间 |
| --- | --- | --- | --- | --- |
| 批次 2 收口（UIBackgroundModes audio + 合并态全量） | Codex workspace-write（nohup） | `/tmp/codex-sub/s4-batch2-close.md` | 见 .log | 2026-09-14 07:15 |
| B4 实现会话（返修时 resume） | — | — | `01a09c00-f5e1-74f3-a498-71873b25c733` | — |
| B5 实现会话（返修时 resume） | — | — | `01a09c00-f596-79b1-b3d0-5f3101e3d88b` | — |
| B6 实现会话（返修时 resume） | — | — | `01a09c00-f589-7562-8954-d1d6aaabc77d` | — |
| B7 实现会话（返修时 resume） | — | — | `01a09c00-f58a-7513-81f5-f7757401255b` | — |

批次 1 实现会话（返修时 resume）：B1 `01a09b74-f5a7-7f02-b1e3-cdc7232de023`、B2 `01a09b74-f5a7-7933-bc9b-219b4a42829e`、B3 `01a09b74-f5a7-7a32-bc80-133de4717b46`。批次 1 提交 `1480ad923`。

## 4. 下一步与未决

- 批次 1 已合并：xcodebuild 通过，LegadoCore 327 + appcore-check 99 项 0 失败。批次 2（B4–B7）并行中。
