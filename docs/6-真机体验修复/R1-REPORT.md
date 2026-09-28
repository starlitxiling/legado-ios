# 轮次 6 R1 返修报告

起点 8235d2fe2；固定 Kotlin 2bdd3c58b。没有子代理、push 或真实 WebDAV 写入。日志均位于 `.build/round6/`，编译失败不作为业务红灯，UI 执行 0 项不计通过。最终全量回归须在最后提交后执行。

## 单元记录

### F1：完成，33b508cdb
ReaderStyleStore.swift 的路径前缀为 App/Sources/Features/Reader/。`ReaderStyleStore.swift:33` 跳过回退加载的偏好覆盖，`:190` 先在同一 backup_files 存储保留原字节，使用毫秒时间与 UUID 防止同名覆盖；保存失败继续阻止写回。部分导入回退也备份输入。测试为 `tools/appcore-check/Tests/ReaderAdvancedCheckTests/ReaderInterfaceConfigTests.swift:8`。
红灯 r1-f1-red3.log，断言 testFallbackPreservesOriginalBytesBeforeSelectionAndEditing：`Executed 1 test, with 8 failures`；绿灯 r1-f1-green2.log：`Executed 10 tests, with 0 failures`；UI r1-f1-ui.log：`Executed 1 test, with 0 failures`。r1-f1-red/red2 的编译错误为测试接线错误，不计红灯。

### F2：完成，ff3db052b
`Packages/LegadoCore/Sources/LegadoCore/Storage/Repositories/BookshelfRepository.swift:28` 置顶同时更新 order、durChapterTime；`App/Sources/Features/Bookshelf/BookshelfView.swift:401` 不再改排序。Kotlin 语义一致。测试 `BookshelfCacheParityTests.testPinUpdatesReadTimeWithoutChangingGroupSort`。
红灯 r1-f2-red.log：`Executed 1 test, with 1 failure`；绿灯 r1-f2-green.log：`Executed 6 tests, with 0 failures`；UI r1-f2b-ui.log：`Executed 1 test, with 0 failures`。r1-f2-ui.log 为等待断言失败，已改为等待菜单关闭与元素相对顺序。

### F3：完成，d00a11e40
`App/Sources/Features/Rss/RssViewModels.swift:18` 等 18 处界面错误统一 presentation；Bookshelf 日志保留。`Packages/LegadoCore/Sources/LegadoCore/LocalizedErrors.swift:11` HTTP 只保留 host/path；`App/Sources/Features/Reader/Paginator.swift:54` 分页错误中文化；`tools/appcore-check/Tests/BookshelfAdvancedCheckTests/ErrorPresentationTests.swift:32` 扫描原始错误、插值，豁免限完整日志语句，允许清单为 0。
红灯 r1-f3-red.log（扫描与 testPaginationErrorsAreLocalized）：`Executed 11 tests, with 3 failures`；r1-f3-core-red.log（testHTTPFailureOmitsCredentialsQueryAndFragment）：`Executed 1 test, with 5 failures`。绿灯 r1-f3-green.log：`Executed 39 tests, with 0 failures`；r1-f3-core-green.log：`Executed 3 tests, with 0 failures`；r1-f3-ui.log：`Executed 1 test, with 0 failures`。

### F4：完成，2b705431e
`App/Sources/Features/Reader/ReaderViewModel.swift:238` 确认非本地且书源不存在才自动换源；`ReaderMenuView.swift:37` 手动入口先取消后台换源。`App/Sources/Shared/ErrorPresentation.swift:13` 仅任务已取消时隐藏 URL cancelled；`Packages/LegadoCore/Sources/LegadoCore/Network/HTTPSessionPool.swift:92` 会话失效、TLS 拒绝、代理认证失败保留网络错误原因。TLS 证据为离线委托回调，未访问真实 TLS 服务。
红灯 r1-f4-red.log（testExistingSourceServerFailureDoesNotStartRecovery）：`Executed 1 test, with 2 failures`；r1-f4-cancel-red.log（testNetworkFallbacksAndCancellation）、r1-f4-core-red.log（testRejectedTLSChallengeProducesVisibleCertificateFailure）：各 `Executed 1 test, with 1 failure`。绿灯 r1-f4-green.log：`Executed 24 tests, with 0 failures`；r1-f4-core-green.log：`Executed 2 tests, with 0 failures`；r1-f4-ui.log：`Executed 1 test, with 0 failures`。

### F5：完成，79002b24d
`Packages/LegadoCore/Sources/LegadoCore/Storage/Repositories/BookSourceRepository.swift:37` 精确优先、规范化唯一匹配；`App/Sources/Features/Reader/ReaderViewModel.swift:162` 打开非本地书后保存规范 origin。`SourceURLNormalizationTests.swift:5` 私有备份仅内存读取与临时目录结果，不入库。
红灯 r1-f5-red.log（testNormalizedOriginIsSavedOnlyForUniqueMatch）：`Executed 1 test, with 8 failures`；绿灯 r1-f5-green.log：`Executed 8 tests, with 0 failures`；真实备份 r1-f5-fixture-green.log：`Executed 1 test, with 0 failures`。4198 源、24 缺源书接回 13 本，7 本各有 3 个近似源而不改挂，4 本无源。初次样本断言误以为 20 本均唯一（r1-f5-fixture.log：`Executed 1 test, with 1 failure`），已按实测歧义修正。专属 UI 未运行，主机已验证打开与保存。

### F6：完成，提交见本单元 Git 记录
`App/Sources/Features/Reader/ReaderStyleStore.swift:86` 修改下划线字段写版本 1；`Packages/LegadoCore/Sources/LegadoCore/Reader/ReaderStyleArchive.swift:10` 导出必写版本 1。Android 下划线全局共享，iOS 仍按样式存储，未改模型。
红灯 r1-f6-red.log（testUnderlineEditsAndExportSetAndroidVersion）：`Executed 1 test, with 2 failures`；绿灯 r1-f6-green.log：`Executed 11 tests, with 0 failures`；r1-f6-ui.log：`Executed 1 test, with 0 failures`，补齐 B4a 旧日志 0 项的无效证据。

## 真机验收清单
安装前提：手机旧版标识为 com.starlitxiling.legado.ios，覆盖包须使用该标识及有效描述文件；不改 App/project.yml，不能直接安装默认标识包。
F1：恢复损坏或部分损坏阅读样式，进入阅读、选择并修改样式；阅读可用，加载回退不改变原阅读偏好，存储保留 broken 备份原文。
F2：书架按阅读时间排序，长按非首本置顶；该书排第一，全局与分组排序仍为阅读时间。
F3：订阅加号导入损坏 JSON，或用失效订阅源加载正文；显示中文操作名与原因。含 query 的书源 HTTP 错误不显示 query。
F4：启用自动换源，现有源返回服务器错误时只显示错误及手动换源；删除对应源后打开书籍才自动查找，手动换源会停止后台查找。
F5：恢复同一 Android 备份后打开原 24 本缺源书；13 本接回且重开保持，7 本歧义与 4 本无对应源仍提示缺源，手动选择所需源。
F6：界面面板修改下划线并关闭重开，设置保留；导出样式在 Android 导入，下划线不再因版本 0 重置。
