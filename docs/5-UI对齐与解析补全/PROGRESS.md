# 轮次 5 执行进度

## 当前阶段

- 2026-09-22：P0-P9、U0-U9 实现与本机回归已交付；计划仍有外部验收和真实样本覆盖缺口，不能标为全部验收完成。
- 最近业务提交：`bbe2b6a5a`；最终测试修正和报告随本文件提交，完整记录见 SUMMARY.md / REVIEW.md。
- 起始提交：`30d180ecf`；Kotlin 固定规格：`2bdd3c58b`。
- 用户最新要求：全部由主会话执行，不启动子代理；暂不进行 iPhone 真机测试。没有安装或测试已连接 iPhone。
- 本机没有 `/review-loop`，按 code-review-excellence 自行审查；未推送，WebDAV 凭据仅用于读取。

## 任务表

| 任务 | 状态 | 执行 | 产物 | 验证 |
| --- | --- | --- | --- | --- |
| P0 基线及轮次 4 收尾 | 完成 | 历史协作后主会话核验 | ../4-收尾与真机验证/SUMMARY.md | 已拆分提交 |
| P1/P2/P3a-h 解析与宿主 | 完成 | 主会话 | docs/spec/js-host-compat.md 等 | Core 747/0 |
| P4/P5/P6 四流程、净化、网络 | 完成 | 主会话 | WebBook / content-compat / network-compat | 离线契约通过；真实固定 8 源 CLI 8/8、模拟器 7/8 |
| P7/P8 本地书、书架与缓存 | 完成 | 主会话 | localbook-compat / storage-notes | 十格式导入末章和图片 UI 通过 |
| P9 JSONPath/XPath | 完成 | 主会话 | jsonpath-completion / xpath-compat | Core 通过，Java 原依赖对拍通过 |
| U0-U9 界面与设置 | 完成 | 主会话 | App/Sources / assets/ | App 322/0；最终 25 项 UI 均有通过记录 |
| 全量搜索冒烟 | 完成 | 主会话 | ALL-SOURCES.md | 4198 条首轮；189 条相关重测后合并 356 通过 |
| 精选真实四流程数量门槛 | 完成 | 主会话 | REAL-SOURCES-FINAL.md | 17/20，超过 16/20 门槛 |
| 最终构建与包 | 完成 | 主会话 | dist/Legado-1.0-bbe2b6a5a.ipa | Release archive 成功，ZIP CRC 校验通过 |
| Android 互导与同屏 | 待核验 | 主会话 | DEVICE-READING-2026-09-22.md | 无设备/SDK/AVD，官方两域名及另一 SSL 客户端均连接失败 |
| 真实覆盖与失败定因 | 待核验 | 主会话 | ALL-SOURCES.md / REAL-SOURCES-FINAL.md | 缺纯 JS 样本；登录样本未全流程通过；526 条待核、3 条 Java 类缺口 |
| 两次 iPhone 验收 | 待核验 | 按用户要求暂缓 | DEVICE-READING-2026-09-22.md | 未测整架更新、真机阅读和内存峰值 |

## 执行方式与证据

无在途代理或测试进程。后半程实现、测试、审查与提交全部由主会话完成。历史分项结果已汇总到 SUMMARY.md，原始日志保留在 .build/round5。

最终 Core 747/0、App 322/0、WebBook CLI 5/0、conformance CLI 7/0；语料仍为 134/142，8 条替换预览 unsupported。UI 首轮 23/25，两类测试修正后 8/8，合并 25 个唯一用例的最新结果均通过；见 final-ui.xcresult / final-ui-retry.xcresult。

## 下一步与未决问题

恢复 Android 可执行环境后完成备份应用内恢复与并排截图，进一步对拍待核书源；取得纯 JS 真实样本后补覆盖。iPhone 验收仅在用户恢复此项工作后执行，不将模拟器结果冒充真机指标。当前无可继续推进的本机实现门禁。

P4-8 按固定 Kotlin 可执行规格收口：SearchBook.kt:65、BookChapter.kt:118 按 URL 判断相等；计划的全字段去重描述与源码及章节主键冲突，以源码为准。
