# 进度（阶段 2 · 数据与网络，轮次 1）

> 新会话先读本文件。最后更新：2026-09-13 15:00（本机时钟）。

## 1. 当前位置

- 阶段 2 轮次 1，在 `ios` 分支直接开发（orphan 分支不开 round worktree）。起点 `bbe6a94c3`；U1 / U3 / U5 已提交 `22c9f65de`（上一条 `4ac518eb8` 只含两份文档，源码在本条）。
- 目标已由人类升级为「一直做到 iOS 应用可构建」（阶段 2 → 3 → 4 部分 → 5）。
- WebDAV 测试凭据在 `.env.local`（gitignored），只读使用。

## 2. 任务表

| 单元 | 状态 | 通道 | 产物 | 验证 |
| --- | --- | --- | --- | --- |
| U1 网络层（HttpClient / URLSession / 字符集 / Cookie） | 完成（1 轮复审 6 条全修；PSL 静态表由 tools/psl 生成） | Codex | `Packages/LegadoCore/Sources/LegadoCore/Network/` | 假客户端回放测试 |
| U3 实体与导入（Codable + Gson 宽松语义） | 完成（1 轮复审 6 条全修；隔离副本 149 测试） | Codex | `Packages/LegadoCore/Sources/LegadoCore/Entities/`、`Import/` | 合成书源 JSON round-trip |
| U5 GRDB schema 与 Repository | 完成（1 轮复审 3 条全修；`docs/spec/storage-notes.md`） | Codex | `Packages/LegadoCore/Sources/LegadoCore/Storage/` | 内存库单测 |
| U2 宿主网络方法 + 完整 AnalyzeUrl 执行器 | 完成（1 轮复审 6 条：5 修 + Cookie 优先级经回源确认保留 Kotlin 行为；工作区 215 测试） | Codex | `AnalyzeUrl/AnalyzeUrlExecutor.swift`、`JsEngine/JavaHostNetwork.swift`、`Network/CacheManager.swift` | 假客户端 |
| U4 WebBook 流程 | 在途 | Codex | `Sources/LegadoCore/WebBook/` | fixture 端到端 |
| U6 备份与 WebDAV | 在途 | Codex | `Sources/LegadoCore/Backup/`、`WebDAV/` | 假客户端；真实服务器只读冒烟由主会话跑 |

## 3. 在途子 agent

| 任务 | 通道 | 输出 | session id | 派出时间 |
| --- | --- | --- | --- | --- |
| U1 实现会话（返修时 resume） | — | — | `01a098ef-b5b4-7802-85c8-08ee5c6d33c9` | — |

## 4. 下一步与未决

- 三个单元回收后各自独立复审、返修、提交；再派 U2，随后 U4，最后 U6。
- 真实 WebDAV 只读冒烟与真实书源冒烟由主会话在 U6 / U4 之后各跑一次，结果记入 SUMMARY。
