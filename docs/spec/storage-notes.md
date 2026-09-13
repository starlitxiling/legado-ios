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

依据：Kotlin `cb664b84d` 的 `BookDao.kt:220`、`BookChapterDao.kt:37`、`ReplaceRuleDao.kt:19`、`ReplaceRuleDao.kt:38` 和 `SearchBookDao.kt:6`。
