# 进度（阶段 2 · 数据与网络，轮次 1）

> 新会话先读本文件。最后更新：2026-09-13 13:50（本机时钟）。

## 1. 当前位置

- 阶段 2 轮次 1，在 `ios` 分支直接开发（orphan 分支不开 round worktree）。起点 commit `bbe6a94c3`。
- 目标已由人类升级为「一直做到 iOS 应用可构建」（阶段 2 → 3 → 4 部分 → 5）。
- WebDAV 测试凭据在 `.env.local`（gitignored），只读使用。

## 2. 任务表

| 单元 | 状态 | 通道 | 产物 | 验证 |
| --- | --- | --- | --- | --- |
| U1 网络层（HttpClient / URLSession / 字符集 / Cookie） | 完成（1 轮复审 6 条全修；PSL 静态表由 tools/psl 生成） | Codex | `Packages/LegadoCore/Sources/LegadoCore/Network/` | 假客户端回放测试 |
| U3 实体与导入（Codable + Gson 宽松语义） | 完成（1 轮复审 6 条全修；隔离副本 149 测试） | Codex | `Packages/LegadoCore/Sources/LegadoCore/Entities/`、`Import/` | 合成书源 JSON round-trip |
| U5 GRDB schema 与 Repository | 完成（1 轮复审 3 条全修；`docs/spec/storage-notes.md`） | Codex | `Packages/LegadoCore/Sources/LegadoCore/Storage/` | 内存库单测 |
| U2 宿主网络方法 + 完整 AnalyzeUrl 执行器 | 在途（首轮停机核对后决定纳入完整执行器：限流、type、bodyJs、webView 桩） | Codex | `AnalyzeUrl/AnalyzeUrlExecutor.swift`、`JsEngine/JavaHostNetwork.swift`、`Network/CacheManager.swift` | 假客户端 |
| U4 WebBook 流程 | 待办（依赖 U2 + U3） | Codex | `Sources/LegadoCore/WebBook/` | fixture 端到端 |
| U6 备份与 WebDAV | 待办（依赖 U1 + U3 + U5） | Codex | `Sources/LegadoCore/Backup/`、`WebDAV/` | 假客户端；真实服务器只读冒烟由主会话跑 |

## 3. 在途子 agent

| 任务 | 通道 | 输出 | session id | 派出时间 |
| --- | --- | --- | --- | --- |
| U2 宿主网络方法（resume 续跑 r2） | Codex workspace-write（nohup） | `/tmp/codex-sub/s2-u2-javahost-net-r2.md` | `01a09907-e5e1-7482-8822-1cc9e4093c4b` | 2026-09-13 13:40 |
| U1 实现会话（返修时 resume） | — | — | `01a098ef-b5b4-7802-85c8-08ee5c6d33c9` | — |

## 4. 下一步与未决

- 三个单元回收后各自独立复审、返修、提交；再派 U2，随后 U4，最后 U6。
- 真实 WebDAV 只读冒烟与真实书源冒烟由主会话在 U6 / U4 之后各跑一次，结果记入 SUMMARY。
