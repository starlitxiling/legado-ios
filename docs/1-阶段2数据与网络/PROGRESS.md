# 进度（阶段 2 · 数据与网络，轮次 1）

> 新会话先读本文件。最后更新：2026-09-13 18:25（本机时钟）。

## 1. 当前位置

- 阶段 2 轮次 1，在 `ios` 分支直接开发（orphan 分支不开 round worktree）。起点 `bbe6a94c3`；U1 / U3 / U5 在 `22c9f65de`，U2 在 `f2b41b1dd`，均已推送。
- 目标已由人类升级为「一直做到 iOS 应用可构建」（阶段 2 → 3 → 4 部分 → 5）。
- WebDAV 测试凭据在 `.env.local`（gitignored），只读使用。

## 2. 任务表

| 单元 | 状态 | 通道 | 产物 | 验证 |
| --- | --- | --- | --- | --- |
| U1 网络层（HttpClient / URLSession / 字符集 / Cookie） | 完成（1 轮复审 6 条全修；PSL 静态表由 tools/psl 生成） | Codex | `Packages/LegadoCore/Sources/LegadoCore/Network/` | 假客户端回放测试 |
| U3 实体与导入（Codable + Gson 宽松语义） | 完成 + 真实数据返修（根因：词法解析对超长字符串的 ICU 正则内部错误，改线性扫描；真实 4198 条全部解码；Kotlin 恢复语义核实为整数组失败不逐条跳过） | Codex | `Packages/LegadoCore/Sources/LegadoCore/Entities/`、`Import/` | 合成书源 JSON round-trip |
| U5 GRDB schema 与 Repository | 完成（1 轮复审 3 条全修；`docs/spec/storage-notes.md`） | Codex | `Packages/LegadoCore/Sources/LegadoCore/Storage/` | 内存库单测 |
| U2 宿主网络方法 + 完整 AnalyzeUrl 执行器 | 完成（1 轮复审 6 条：5 修 + Cookie 优先级经回源确认保留 Kotlin 行为；工作区 215 测试） | Codex | `AnalyzeUrl/AnalyzeUrlExecutor.swift`、`JsEngine/JavaHostNetwork.swift`、`Network/CacheManager.swift` | 假客户端 |
| U4 WebBook 流程 | 完成（1 轮复审 12 条全修 + 精准搜索按 checkKeyWord / precisionSearch；替换 JS 超时不能抢占死循环脚本为已知限制） | Codex | `Sources/LegadoCore/WebBook/` | fixture 端到端 |
| U6 备份与 WebDAV | 完成（1 轮复审 3 条全修 + 真实包 zip 修复 + 冒烟工具接入有界客户端；274 测试全绿）。**真实服务器只读冒烟通过**：711 个备份、最新一份导入 books 82 / book_sources 4198 / replace 20 / readRecord 138 / bookmarks 154 / groups 9，无失败文件 | Codex | `Sources/LegadoCore/Backup/`、`WebDAV/` | 假客户端；真实服务器只读冒烟由主会话跑 |

## 3. 在途子 agent

| 任务 | 通道 | 输出 | session id | 派出时间 |
| --- | --- | --- | --- | --- |
| 真实书源冒烟工具 | Codex workspace-write（nohup） | `/tmp/codex-sub/s2-webbook-smoke.md` | 见 .log | 2026-09-13 18:05 |
| U4 实现会话（返修时 resume） | — | — | `01a09933-6640-7092-a247-6a629dc24308` | — |
| U6 实现会话（返修时 resume） | — | — | `01a09933-6639-7230-b074-9d9b10b7f5db` | — |

已完成单元的实现会话（返修时 resume）：U1 `01a098ef-b5b4-7802-85c8-08ee5c6d33c9`、U3 `01a098ef-b4b3-7621-a834-4f7289785a49`、U5 `01a098ef-b4e1-7b71-be98-540ad62527c3`、U2 `01a09907-e5e1-7482-8822-1cc9e4093c4b`。

## 4. 下一步与未决

- 六个单元全部完成；WebDAV 只读冒烟已通过。剩余：真实书源冒烟（工具在写，候选书源已挑在 scratchpad `smoke-source-*.json`，首选轻小说 / 刺猬猫等平台的公开源），通过后写 SUMMARY 收口阶段 2，进入阶段 3（SwiftUI MVP）。
