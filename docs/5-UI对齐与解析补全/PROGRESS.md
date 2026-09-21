# 轮次 5 执行进度

## 当前阶段

- 2026-09-21：P0、批次 1、P5/P6/U1/U2/U3 已完成；当前 P7 本地书，P4 真实门禁与去重取舍待收口。
- 起始提交：`30d180ecf`；P0 已拆为 ff6f50452、f82ddf72c、284834405 三笔本地提交。
- 用户 2026-09-21 最新要求：持续完成全部计划，暂不进行 iPhone 真机测试；两次真机验收均暂缓，其余回归继续。
- 用户最新指示：全部由主会话亲自执行，不再启动子代理。已停止全部在途子代理，保留已完成产出。
- 本机未找到 `/review-loop`，使用 `code-review-excellence` 检查，后续由主会话自行审查与测试。

## 任务表

| 任务 | 状态 | 通道 | 产物 | 验证 |
| --- | --- | --- | --- | --- |
| P0 PDF 标题与 Core 基线 | 完成 | astra / medium | `.build/round5/p0-report.md` | Core 549/0；AppCore PDF 5/0，已抽查 diff |
| P0 既有修复独立审查与真机条件 | 完成 | astra / medium | `.build/round5/p0-review.md` | 发现备份口令接线、零用例假绿；设备开发模式开启 |
| P0 备份接线与运行器返修 | 完成 | 已收回 | `.build/round5/p0-fixes-report.md` | AppCore 236/0；CLI 7/0；已核验 diff |
| P0 iOS 构建与冷启动测试 | 完成 | 已收回 | `.build/round5/p0-ios-report.md` | generic iOS 构建与模拟器启动测试通过 |
| P7 压缩依赖前置实证 | 完成 | 已收回 | `.build/round5/archive-probe.md` | 3/0 与 generic iOS 构建；尚未接入业务 |
| P0 拆分提交与轮次 4 总结 | 完成 | 主会话 | `docs/4-收尾与真机验证/SUMMARY.md` | 已验收并拆分提交 |
| P1 七项解析修复 | 完成 | 主会话 | RuleParityTests / .build/round5/p1-*.log | Core 562/0、AppCore 236/0、CLI 7/0 |
| P2 脚本上下文与 URL 变量宿主 | 完成 | 主会话 | ScriptContextTests / .build/round5/p2-*.log | Core 574/0、AppCore 236/0、CLI 7/0 |
| P3a UI 与系统宿主 | 完成 | 主会话 | JavaHostPlatformTests / ScriptHostConfigurationTests | Core 580/0、AppCore 238/0、generic iOS 构建通过 |
| P3b 字节桥与编解码 | 完成 | 主会话 | JavaHostEncodingTests / .build/round5/p3b-*.log | Core 586/0、AppCore 238/0、CLI 7/0 |
| P3c 加密与 CryptoJS | 完成 | 主会话 | JavaHostCryptoTests / .build/round5/p3c-*.log | Core 595/0、AppCore 238/0、CLI 7/0、iOS 构建通过 |
| P3d 时间 | 完成 | 主会话 | JavaHostTimeTests / .build/round5/p3d-*.log | Core 599/0 |
| U0 主题基础 | 完成 | 主会话 | ThemeStoreTests / assets/theme-*.png | AppCore 244/0；iOS 构建与模拟器 5 项通过 |
| U9 通用组件 | 完成 | 主会话 | Shared/Components / assets/components*.png | 逻辑 3/0；iOS 图标与交互 2/0 |
| 批次 1 门禁 | 完成 | 主会话 | .build/round5/batch1-*.log | Core 599/0、AppCore 247/0、CLI 7/0；iOS 构建/启动通过 |
| 批次 2：P4 | 在途 | 主会话 | WebBook 四流程 | Core 634/0、AppCore 249/0、CLI 7/0、iOS 构建通过；真实门禁未达标 |
| 批次 2：P5 | 完成 | 主会话 | docs/spec/content-compat.md | Core 649/0、AppCore 254/0、iOS 构建通过 |
| 批次 2：P6 | 完成 | 主会话 | docs/spec/network-compat.md | Core 667/0、AppCore 256/0、iOS 构建通过 |
| 批次 2：U1 | 完成 | 主会话 | RootTabView / MainTabObserver | 模拟器 UI 4 项及回调 1 项通过，iOS 构建通过 |
| 批次 2：U2 | 完成 | 主会话 | BookshelfLayout / 书单与远程入口 | Core 667/0、AppCore 268/0；模拟器 UI 3 项与 iOS 构建通过 |
| 批次 2：U3 | 完成 | 主会话 | SearchView / SearchScope / assets/u3-* | Core 667/0、AppCore 272/0、CLI 7/0；模拟器 UI 2 项通过 |
| P7-1 UMD | 完成 | 主会话 | UmdFile / localbook-compat.md | Core 670/0 + 缓存测试；AppCore 272/0；iOS 构建通过 |
| P7-2 压缩包 | 完成 | 主会话 | BookArchive / LocalImport / RemoteBooks | Core 675/0、AppCore 275/0；iOS 构建通过 |
| 批次 3-5 | 待办 | 主会话 | 按 PLAN.md | 按批次门禁 |

## 执行方式

无在途代理。后续实现、测试、审查、提交全部由主会话逐项执行。已有报告仅作历史证据。

## 下一步

最近提交 98f7b32f5（UMD/AZW）；P7 压缩包后端及导入完成，继续其它本地书项目；P4 流程基础已验证，真实 CLI 4/40、模拟器 4/8，未达门禁，见 REAL-SOURCES-P4.md；P5/P6 已完成，继续 P7 本地书。全程不推送；WebDAV 凭据只用于读取。

P4-8 待用户选择：Kotlin SearchBook/BookChapter 实际按 URL 去重，计划全字段去重与章节主键冲突。临时方案已隔离到 .build/round5/p4-fullfield-proposal.patch，主实现恢复既有 URL 行为以继续回归；不视为用户已决策。
