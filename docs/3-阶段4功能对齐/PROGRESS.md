# 进度（阶段 4 · 功能对齐，轮次 3）

> 新会话先读本文件。最后更新：2026-09-14 15:00（本机时钟）。

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
| B8 书源编辑进阶 | 完成（`2ebc26ecf`；复审 5 条已修） | LegadoCore `Debug/ Export/`、App `Features/Sources/{Edit,Debug}` 等 | 离线测试 |
| B9 阅读器进阶 | 完成（`2ebc26ecf`；复审 5 条已修） | LegadoCore `Reader/`、App `Features/Reader/*` | 离线测试 |
| B10 书架进阶与下载 | 完成（`2ebc26ecf`；复审 6 条已修 + BGTask 配置） | LegadoCore `Cache/`、App `Features/{Bookshelf,Download,BookDetail/Edit}` | 离线测试 |
| B11 RSS | 待核验 r2（7 条已修；RSS 专项 24 通过） | LegadoCore `Rss/`、App `Features/Rss` | 离线测试 |
| B12 漫画 / 音频源 | 待核验 r2（4 条已修；本单元 24 通过） | 见 PLAN | — |
| B13 备份上传与设置 | 待核验 r2（5 条已修，核心 34 通过；App 新增 8 用例待 B13b 的 AppPreferences 落地后在合并态验证） | LegadoCore `Backup/`、App `Features/{Backup,Settings}` | 离线测试，只用假客户端 |
| B14 局域网 Web 服务 | 待核验 r2（8 条已修：x-legado-token 鉴权、CORS、/cover /image、排序、previewText 迁移、异常响应、NWPathMonitor、/addLocalBook；WebApi 16 + WebService 3 通过；WebSocket 未实现） | LegadoCore `Web/`、App `Features/WebService` | 离线测试 |
| B15 实体与表补齐 | 待核验 r2（7 条已修 + 恢复顺序；实体 14 + App 5 + Core 全量 496/496） | LegadoCore `Entities/ Storage/ Backup/`、App `Features/Settings` | 离线测试 |
| B13b 设置全集对齐 | 待核验 r3（7 条已修；Core 48 + App 59，Core 全量 520；launcherIcon 需主工程备用图标资源 → 收口 2） | App `Features/Settings`、`docs/spec/settings-compat.md` | — |

## 3. 在途子 agent

| 任务 | 通道 | 输出 | session id | 派出时间 |
| --- | --- | --- | --- | --- |
| B11 实现会话（返修时 resume） | — | — | `01a09c64-f5b3-7872-b56c-750dcab9fbda` | 2026-09-14 10:10 |
| B12 实现会话（返修时 resume） | — | — | `01a09c64-f5b2-78a3-a99b-90d874530a09` | 2026-09-14 10:10 |
| B13 实现会话（返修时 resume） | — | — | `01a09c64-f5b2-7951-8295-fe7895c79fa9` | 2026-09-14 10:10 |
| 批次 4 收口 2（备用图标 + appcore-check 全量） | Codex workspace-write（nohup） | `/tmp/codex-sub/s4-batch4-close2.md` | 见 .log | 2026-09-14 15:00 |
| B13b 实现会话（返修时 resume） | — | — | `01a09c85-8613-7a33-b19a-54feebfd8d3b` | — |
| B15 实现会话（返修时 resume） | — | — | `01a09c72-95e3-7480-bdbe-a23d99f50e98` | — |
| B14 实现会话（返修时 resume） | — | — | `01a09c64-f5b2-7331-b36d-4724a6ab5674` | 2026-09-14 10:10 |

批次 1 实现会话（返修时 resume）：B1 `01a09b74-f5a7-7f02-b1e3-cdc7232de023`、B2 `01a09b74-f5a7-7933-bc9b-219b4a42829e`、B3 `01a09b74-f5a7-7a32-bc80-133de4717b46`。批次 1 提交 `1480ad923`。

## 4. 下一步与未决

- 批次 1–3 已合并推送（`2ebc26ecf`）。批次 4 全部单元返修完毕；收口 1 通过（Core 513、App 220×2）；B13b r3 后 Core 520；收口 2 在跑（备用图标 + App 全量）。之后：xcodegen + xcodebuild（DerivedData 已删，全量重建）→ 提交推送 → 阶段 4 SUMMARY → memory。
