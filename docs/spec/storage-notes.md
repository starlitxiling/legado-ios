# Storage 接入说明

文件数据库由 `AppDatabase.file(at:)` 创建，使用 GRDB 7.11.1 的 DatabasePool，并启用 `observesSuspensionNotifications`。内存库不监听挂起通知。

## 应用生命周期

- App 层仍需在 `UIApplicationDelegate.applicationDidEnterBackground(_:)` 中调用 `database.suspend()`；若持有系统允许的后台任务，应在后台任务到期前挂起。
- 回到前台时，在恢复数据库业务前调用 `database.resume()`。不要仅依赖 SwiftUI 单个窗口的非活跃状态判断整个应用是否进入后台。
- 合法后台任务如需访问数据库，应先恢复，完成后在应用再次挂起前调用 `suspend()`；应用层负责协调重叠任务与生命周期事件。
- 挂起期间写入可能抛出 `SQLITE_INTERRUPT` 或 `SQLITE_ABORT`；App 层应捕获错误，在恢复后根据业务幂等性重试，不能当成成功。WAL 读取仍可能成功。
- 两个接口发送 GRDB 的进程级通知，会影响所有启用监听的数据库，并非只影响调用接口的那个实例。不要在数据库事务内调用生命周期接口。
- 此处未接入 UIKit，也未验证 iOS 真机进入后台及系统挂起；这些仍需 App 层完成。

依据：GRDB 7.11.1 的 `GRDB/Core/Configuration.swift:131`、`GRDB/Core/Database.swift:1171`、`GRDB/Core/DatabasePool.swift:318` 与 `GRDB/Documentation.docc/DatabaseSharing.md:202`。

## 导入与查询

- 书籍普通 `upsert` 按主键更新并保留章节；导入时调用 `replaceByIdentity(_:)`，采用 Room REPLACE，同名同作者的旧 URL 及其章节会被删除。同 URL 的 REPLACE 也会删除旧章节。
- 章节插入采用 REPLACE，同一本书同一序号的新 URL 替换旧记录；整本章节替换中重复序号以后写入项为准。
- 替换规则用 `list(groupName:)` 做分隔符规范化后的整组匹配；`listUngrouped()` 查询 NULL、空白及“未分组”。只有分隔符的字段不属于 Kotlin 定义的未分组。
- MVP 不含 Kotlin 的书籍备忘表，因此没有备忘迁移逻辑。

依据：Kotlin `2bdd3c58b` 的 `BookDao.kt:220`、`BookChapterDao.kt:37`、`ReplaceRuleDao.kt:19`、`ReplaceRuleDao.kt:38` 和 `SearchBookDao.kt:6`。

## 书架与缓存（轮次 5 P8）

- 加书架以事务写入 `min(order) - 1`；已存在的书更新原记录，保留章节。遇到最小整数时先稳定重排，避免溢出。
- 本地 TXT 的缓存状态直接为真；显式缓存任务仍生成可导出的正文文件。
- 改名后保留旧目录，读取按 URL 的 MD5 后缀寻找历史目录；清理也保留同一 URL 的旧名称目录。对应 Android `BookHelp.updateCacheFolder`，避免文件迁移中断导致丢缓存。
- 清理仅扫描下载根目录的 `book_cache` 和 Android 兼容 `epub` 目录，移除不在书架中的书；拒绝符号链接根目录，不跟随子链接。iOS EPUB 直接读取压缩包，不创建解压目录。导入临时文件由导入事务清理，分享文件由各导出流程管理；漫画窗口裁剪仍由漫画阅读进度流程执行。
- 阅读器开启预下载且距离末章少于三章时，在数据库原子领取十分钟更新窗口，然后更新目录；失败也保留本次检查时间，避免重复请求。
- 模拟追读的最新章节标题沿用 WebBook 与 BookshelfAdvancedRepository 已实现的模拟索引，非恒取末章。
- 更新结果区分缺少书源、超时、解析、网络和其他错误；缺少书源可进入预填书名的搜索。

对拍基线：Kotlin `2bdd3c58b` 的 `BookHelp.kt:151-201,631-645`、`ReadBook.kt:1785`、`BookInfoViewModel.kt:489-505`。专项测试 `BookshelfCacheParityTests`、`ReaderChapterUpdateTests`；模拟器交互 `BookshelfLayoutUITests.testRefreshFailuresOfferReplacementSearch`。本轮未进行 iPhone 真机验证。
