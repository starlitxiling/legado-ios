# 轮次 6 独立交叉复审（2026-09-28）

4 个 opus-explorer 只读复审（A1-A3 / A4 / B / C+测试真实性），主会话抽查标 [已核]。全部为静态审查，未跑测试、未真机。

## 实现缺陷
| P | 问题 | 证据 |
| --- | --- | --- |
| P1 [已核] | 样式解码回退只在内存；用户一改样式 persist() 用预设覆盖原 readConfig.json | ReaderStyleStore.swift:32-46,175-192 |
| P1 [已核] | 置顶永久把分组排序与全局 bookshelfSort 改成手动 | BookshelfView.swift:403-410；Android BookInfoViewModel.kt:486-494 |
| P1 存疑 [已核一半] | 滚动模式面板打开时 value 先写后 return，不刷新；关闭后 externalSeek 为假导致位置错 | ScrollPageContainer.swift:75-78 |
| P1 存疑 | 背景图每页各自解码、相册图不缩放、滚动三章全页非懒加载 VStack，内存风险 | ReaderInfoView.swift:88-97、ReaderView.swift:542 |
| P1 | Rss/Browser 18 处 String(describing: error) 直出英文与带 token 的完整 URL；守门测试扫不到 | RssViewModels.swift:18 等；ErrorPresentationTests.swift:47-51 |
| P2 [已核] | 任何非取消加载失败都触发后台自动换源并永久迁移书源；Android 仅 bookSource==null | ReaderViewModel.swift:212,355；ReadBookViewModel.kt:192-195 |
| P2 | URLError.cancelled 一律算取消，TLS/代理认证失败被静默 | ErrorPresentation.swift:13；HTTPSessionPool.swift:92,102,107 |
| P2 [已核] | 覆盖模式下一页从右盖入，Android 为当前页左移露出下页+阴影；阈值语义不同 | ReaderPresentationState.swift:37-46；CoverPageDelegate.kt:42-51 |
| P2 [已核] | 从不写 underlineConfigVersion=1，导出到 Android 下划线被重置；iOS 按样式存、Android 全局 | ReadBookConfig.swift:50；Android ReadBookConfig.kt:110-123 |
| P2 | 状态栏图标开关驱动根视图 preferredColorScheme，影响整个 App | ThemeEnvironmentModifier.swift:26 |
| P2 | 仿真翻页纸背固定白色 | SimulationPageTransition.swift:86 |
| P2 | 封面内存缓存在完整 I/O 之后才查；同 bookURL 重导入封面不更新 | RemoteImage.swift:69-87、CoverBitmapCache.swift:15 |
| P2 | 分组菜单单选覆盖原有多分组 | BookshelfView.swift:378-383,415-419 |
| P2 存疑 | 进后台进度刷新无后台任务保护，GRDB 挂起可能打断；250ms 合并路径测试未执行 | ReaderView.swift:278；DatabaseLifecycleCoordinator.swift:42-47 |
| P2 | JsEngineError 约 99 处英文字面量、PaginationError 无中文 | SourceHeaders.swift:32、Paginator.swift:54 |
| P3 | 若干：菜单换源不取消后台换源；详情页双层错误包装；httpStatus 露完整 URL；186 处提示仅 8 处带动作；行距标签偏移；eInk 覆盖书级动画；停止更新计数；局域网权限文案 | 各报告 |

## 验证证据问题
- [已核] B4a-REPORT 声称 b4a-ui3 1/0，实际日志 `Executed 0 tests`。
- [已核] final-ui.log 11:20 早于出包提交 794cc4077（11:26），IPA 代码未经完整回归。
- 未见删测、skip、放宽超时；数字与日志对得上。

## 计划（PLAN.md）自身问题
1. 第 0 节缺源根因 (1) 被真实数据证伪：备份 82 本书无 type==0；24/47 本网络书 origin 不在书源库，才是主因。
2. A4 节「逐处改语义」与第 4 节末条「不做逐处语义改写」矛盾；计数 187 实为 203；遗漏 Rss/Browser；守门判据只认 localizedDescription。
3. 算错 -10534531（应 -10239107）；背景图 24 张实为 14。
4. A2 未规定自动换源触发条件，60 秒超时未标为偏离 Android；A1 缺「回退后不覆盖原文件」验收。
5. B1「下一页从右盖上」与 Android 相反；「半屏回弹」与「1/3 触发」矛盾；B2 行距范围混淆存储与显示。
6. B3 未预告系统 pageCurl 与 Android 仿真差距；滚动模式无内存上限/进度粒度验收。B4 漏下划线全局语义与版本字段。
7. C1「对齐 Android 长按菜单」前提不成立（Android 长按进详情）；「滚动流畅」无指标；进度合并写入未规定退后台/被杀行为。
8. 未覆盖打包签名：包标识 com.legado.ios ≠ 手机 com.starlitxiling.legado.ios，直接装会并存一个空 App。
9. 执行偏离：计划的交叉复审全未执行，全部真机验收未做。

## 补充：24 本缺源书（2026-09-28 核实）
备份 bookSource.json 4198 条即 iOS 已导入的全部，导入无丢失。24 本（11 个 origin）在 Android 原机上同样孤儿（type=24 含 updateError 位；Android 按 bookSourceUrl 精确匹配 BookSourceDao.kt:242）。其中 20 本存在「近似书源」（仅差尾部斜杠 / 空白 / `#…` 后缀），4 本（seobishop、xmkanshu 两个 origin）完全无对应源。是否做规范化匹配属产品决策，待用户定。
