# 轮次 6 R2 返修报告

起点 cdedfce6e；G1–G5 均完成。未 push、未使用子代理、未写真实 WebDAV、未改包标识或依赖、未提交私有备份。日志均在 `.build/round6/`。
路径缩写：A=`App/Sources/`，C=`Packages/LegadoCore/Sources/LegadoCore/`，T=`tools/appcore-check/Tests/`，N=`App/Tests/LegadoTests/`，CT=`Packages/LegadoCore/Tests/LegadoCoreTests/`，K 为主仓库 `app/src/main/java/io/legado/app/`（只读）。

## G1：完成，965d95cc2
`C/Storage/Repositories/BookSourceRepository.swift:34` 恢复按主键精确查询，`:38` 新增 resolveForBookOrigin；`A/Features/Reader/ReaderViewModel.swift:162` 本地书跳过解析，`:166` 同次保存 origin 与 originName，内存实体同步。其他接线文件见下表。
Kotlin 换源经 `K/ui/book/changesource/ChangeBookSourceDialog.kt:497` 调用 toBook，`K/data/entities/SearchBook.kt:125`、`:126` 同时复制 origin、originName；本轮补齐相同名称配对。
红灯断言为 `CT/WebApiTests.swift:5` 的 testDeletingMissingSourceDoesNotDeleteNormalizedNeighbor 与 `T/ReaderCheckTests/ReaderSourceRecoveryTests.swift:7` 的 testNormalizedOriginIsSavedOnlyForUniqueMatch；绿灯覆盖斜杠、空白、fragment、多重匹配以及 X 接回 X/ 和名称保存。
r2-g1-core-red.log：`Executed 1 test, with 2 failures (0 unexpected) in 0.968 (0.972) seconds`；r2-g1-app-red.log：`Executed 1 test, with 4 failures (0 unexpected) in 0.993 (0.994) seconds`；r2-g1-core-green.log：`Executed 18 tests, with 0 failures (0 unexpected) in 10.176 (10.180) seconds`；r2-g1-app-green.log：`Executed 24 tests, with 0 failures (0 unexpected) in 0.388 (0.390) seconds`。

下表列出原 get 的全部调用点及归属（含测试）；完整检索在 `.build/round6/r2-g1-callers.txt`。

| 调用点 | 归属与处理 |
| --- | --- |
| `A/Shared/ImageRepositoryLoader.swift:10` | 精确；封面。 |
| `A/Features/Bookshelf/BookshelfBookListModel.swift:129` | 精确；选定搜索源 ID。 |
| `A/Features/BookDetail/BookDetailViewModel.swift:52`、`:92` | 书籍 origin；详情与书架状态，改用解析 API。 |
| `A/Features/AudioPlay/MediaBookLibrary.swift:32` | 书籍 origin；媒体书，改用解析 API。 |
| `A/Features/BookDetail/BookSourceSwitchView.swift:78` | 精确；对选定书源执行校验。 |
| `A/Features/Sources/SourcesViewModel.swift:134` | 精确；编辑与启用。 |
| `A/Features/Settings/AutoTaskController.swift:65` | 书籍 origin；自动任务，改用解析 API。 |
| `A/Features/Download/DownloadCenterModel.swift:72`、`:203` | 书籍 origin；下载与更新，改用解析 API。 |
| `A/Features/Search/SearchViewModel.swift:185` | 精确；搜索源 ID。 |
| `A/Features/Explore/ExploreViewModel.swift:86` | 精确；删除。 |
| `A/Features/Reader/ReaderSourceReimportView.swift:29` | 精确；重导入源的编辑入口。 |
| `A/Features/Reader/ReaderViewModel.swift:162`、`:255`、`:740` | 书籍 origin；打开、缺源判断、重载，改用解析 API。 |
| `C/Web/WebApi.swift:112`、`:125`、`:189`、`:248` | 全部精确；查询、删除、书籍刷新与内容 API 按任务约束保持精确。 |
| `C/Web/WebSocketRoutes.swift:71` | 精确；调试目标源。 |
| `CT/SourceLoginReviewTests.swift:88`、`CT/SourceCheckerTests.swift:44` | 精确；持久化结果断言。 |
| `CT/WebApiTests.swift:10`、`:15` | 精确；本轮新增缺失源删除断言。 |
| `T/AppCoreCheckTests/SourceImportRevisionTests.swift:22`、`:30`、`:52`、`:57`、`:77` | 精确；导入断言。 |
| `T/AppCoreCheckTests/SourceManagementTests.swift:97`、`:100` | 精确；管理断言。 |
| `T/ReaderCheckTests/ReaderSourceRecoveryTests.swift:20`、`:31`、`:33` | 书籍 origin；规范化、歧义与精确优先，改用解析 API。 |

## G2：完成，40ad5ce9a
`T/ReaderCheckTests/ReaderTests.swift:9` 新增 testDefaultProgressCoalescingWritesOnlyFinalPageWithoutFlush，真实默认 250ms、连续三次 selectPage、等待全部调度任务；SQL trigger 记录实际更新，断言仅一条且为最后进度，断言前不 flush。已更正 `docs/6-真机体验修复/R1-REPORT.md:50` 的错误覆盖声明。
调度逻辑无需修复。红灯为临时禁用 scheduleProgressSave 的变异，任务数、写入记录及最终进度均失败，随后恢复原生产代码。r2-g2-compile/compile2/compile3.log 的接线编译失败不计红灯。
r2-g2-red.log：`Executed 1 test, with 3 failures (0 unexpected) in 0.453 (0.454) seconds`；r2-g2-green.log：`Executed 20 tests, with 0 failures (0 unexpected) in 3.269 (3.274) seconds`。

## G3：完成，f3d8732e5
`A/Features/Reader/ReaderDeviceController.swift:86` 注入 begin/end，`:93` 到期回调同步结束，`:99` 在 end 前清空标识。`N/ReaderProgressBackgroundTaskTests.swift:7` 的 testExpirationEndsSynchronouslyAndOnlyOnce 验证返回前已结束；另两项覆盖正常完成先发生及无效任务。生成物为 `App/Legado.xcodeproj/project.pbxproj`。
r2-g3-red.log：`Executed 3 tests, with 1 failure (0 unexpected) in 0.294 (0.297) seconds`；r2-g3-green.log：`Executed 3 tests, with 0 failures (0 unexpected) in 0.002 (0.009) seconds`。

## G4：完成，84eb1c85c
`A/Features/Reader/ReaderStyleStore.swift:203` 在同一 SQL 写入内按文件名前缀和原始 BLOB 字节去重，不覆盖旧备份。`T/ReaderAdvancedCheckTests/ReaderInterfaceConfigTests.swift:40` 的 testBrokenStyleBackupsDeduplicateOnlyIdenticalContents 对两个文件分别验证重复 load 一份、不同内容两份。
r2-g4-red.log：`Executed 1 test, with 4 failures (0 unexpected) in 0.352 (0.357) seconds`；r2-g4-green.log：`Executed 13 tests, with 0 failures (0 unexpected) in 0.227 (0.232) seconds`。

## G5：完成，3b431b9cb
`T/ReaderCheckTests/ReaderErrorPresentationTests.swift:7` 的 testCancelledTaskRequestHasNoPresentedError 在已取消 Task 内发出模拟请求并得到 URLError.cancelled，断言取消为真、presentation 为空。原分类已满足该正向条件，未修改。
`A/Shared/HeadlessWebView.swift:129`、`:130` 原来直接结束为 -999，未取消 Task 中会产生可展示错误；`:133` 现在仅忽略 URL 域的导航取消，等待替代导航结果，保留超时和其他域错误。`N/HeadlessNavigationTests.swift:8` 的 testInterruptedNavigationKeepsRequestAliveForNextNavigation 回放两种委托，再以超时证明请求仍在；另一项验证同码其他域不被吞。生成物已更新。
r2-g5-red.log：`Executed 2 tests, with 4 failures (0 unexpected) in 0.445 (0.447) seconds`；r2-g5-green.log：`Executed 2 tests, with 0 failures (0 unexpected) in 0.398 (0.400) seconds`；r2-g5-app-green.log：`Executed 3 tests, with 0 failures (0 unexpected) in 0.110 (0.114) seconds`。

## 最终验证与交付边界
全部红绿已核对实际 Executed 行，引用的测试名均在仓库存在。最终命令从 ios 工作树根执行，环境变量和参数沿用 `.build/round6/r1-final-summary.md`，仅将日志和结果目录改为 r2；模拟器完整运行不含 only-testing。
最后一次提交之后运行 Core、App、LegadoTests 与 LegadoUITests；SHA、开始时间和完整计数写入 [最终回归摘要](../../.build/round6/r2-final-summary.md)，对应 r2-final-core/app/ui.log。定点绿灯不能代替最终结果。
没有单元跳过。G3/G5 是 UIKit 接口注入与 WebKit 委托回放，真机系统到期和真实站点中断导航未验证；G1 使用内存库 Web API 路由测试，未访问真实 WebDAV。本轮不出包、不签名、不安装 iPhone；覆盖包须沿用 com.starlitxiling.legado.ios 并有效签名，项目包标识未改。
