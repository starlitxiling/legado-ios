# 轮次 6 R1 返修报告

起点 8235d2fe2；固定 Kotlin 2bdd3c58b。没有子代理、push 或真实 WebDAV 写入。日志均位于 `.build/round6/`，编译失败不作为业务红灯，UI 执行 0 项不计通过。最终全量回归须在最后提交后执行。

## 单元记录

### F1：完成，33b508cdb
ReaderStyleStore.swift 的路径前缀为 App/Sources/Features/Reader/。`ReaderStyleStore.swift:33` 跳过回退加载的偏好覆盖，`:197` 先在同一 backup_files 存储保留原字节，使用毫秒时间与 UUID 防止同名覆盖；保存失败继续阻止写回。部分导入回退也备份输入。测试为 `tools/appcore-check/Tests/ReaderAdvancedCheckTests/ReaderInterfaceConfigTests.swift:40`。
红灯 r1-f1-red3.log，断言 testFallbackPreservesOriginalBytesBeforeSelectionAndEditing：`Executed 1 test, with 8 failures`；绿灯 r1-f1-green2.log：`Executed 10 tests, with 0 failures`；UI r1-f1-ui.log：`Executed 1 test, with 0 failures`。r1-f1-red/red2 的编译错误为测试接线错误，不计红灯。

### F2：完成，ff3db052b
`Packages/LegadoCore/Sources/LegadoCore/Storage/Repositories/BookshelfRepository.swift:28` 置顶同时更新 order、durChapterTime；`App/Sources/Features/Bookshelf/BookshelfView.swift:401` 不再改排序。Kotlin 语义一致。测试 `BookshelfCacheParityTests.testPinUpdatesReadTimeWithoutChangingGroupSort`。
红灯 r1-f2-red.log：`Executed 1 test, with 1 failure`；绿灯 r1-f2-green.log：`Executed 6 tests, with 0 failures`；UI r1-f2b-ui.log：`Executed 1 test, with 0 failures`。r1-f2-ui.log 为等待断言失败，已改为等待菜单关闭与元素相对顺序。

### F3：完成，d00a11e40
`App/Sources/Features/Rss/RssViewModels.swift:18` 等 18 处界面错误统一 presentation；Bookshelf 日志保留。`Packages/LegadoCore/Sources/LegadoCore/LocalizedErrors.swift:11` HTTP 只保留 host/path；`App/Sources/Features/Reader/Paginator.swift:54` 分页错误中文化；`tools/appcore-check/Tests/BookshelfAdvancedCheckTests/ErrorPresentationTests.swift:32` 扫描原始错误、插值，豁免限完整日志语句，允许清单为 0。
红灯 r1-f3-red.log（扫描与 testPaginationErrorsAreLocalized）：`Executed 11 tests, with 3 failures`；r1-f3-core-red.log（testHTTPFailureOmitsCredentialsQueryAndFragment）：`Executed 1 test, with 5 failures`。绿灯 r1-f3-green.log：`Executed 39 tests, with 0 failures`；r1-f3-core-green.log：`Executed 3 tests, with 0 failures`；r1-f3-ui.log：`Executed 1 test, with 0 failures`。

### F4：完成，2b705431e
`App/Sources/Features/Reader/ReaderViewModel.swift:248` 确认非本地且书源不存在才自动换源；`App/Sources/Features/Reader/ReaderMenuView.swift:37` 手动入口先取消后台换源。`App/Sources/Shared/ErrorPresentation.swift:13` 仅任务已取消时隐藏 URL cancelled；`Packages/LegadoCore/Sources/LegadoCore/Network/HTTPSessionPool.swift:92` 会话失效、TLS 拒绝、代理认证失败保留网络错误原因。TLS 证据为离线委托回调，未访问真实 TLS 服务。
红灯 r1-f4-red.log（testExistingSourceServerFailureDoesNotStartRecovery）：`Executed 1 test, with 2 failures`；r1-f4-cancel-red.log（testNetworkFallbacksAndCancellation）、r1-f4-core-red.log（testRejectedTLSChallengeProducesVisibleCertificateFailure）：各 `Executed 1 test, with 1 failure`。绿灯 r1-f4-green.log：`Executed 24 tests, with 0 failures`；r1-f4-core-green.log：`Executed 2 tests, with 0 failures`；r1-f4-ui.log：`Executed 1 test, with 0 failures`。

F4 补充复测：会话失效携带 URL cancelled 时仍转换为连接丢失，避免丢失原因。红灯 r1-f4-session-red.log（testInvalidatedCancelledSessionDoesNotProduceCancellation）：`Executed 1 test, with 1 failure`；绿灯 r1-f4-session-green.log：`Executed 3 tests, with 0 failures`；补充提交见 Git 记录。

### F5：完成，79002b24d
`Packages/LegadoCore/Sources/LegadoCore/Storage/Repositories/BookSourceRepository.swift:37` 精确优先、规范化唯一匹配；`App/Sources/Features/Reader/ReaderViewModel.swift:162` 打开非本地书后保存规范 origin。`Packages/LegadoCore/Tests/LegadoCoreTests/SourceURLNormalizationTests.swift:5` 私有备份仅内存读取与临时目录结果，不入库。
红灯 r1-f5-red.log（testNormalizedOriginIsSavedOnlyForUniqueMatch）：`Executed 1 test, with 8 failures`；绿灯 r1-f5-green.log：`Executed 8 tests, with 0 failures`；真实备份 r1-f5-fixture-green.log：`Executed 1 test, with 0 failures`。4198 源、24 缺源书接回 13 本，7 本各有 3 个近似源而不改挂，4 本无源。初次样本断言误以为 20 本均唯一（r1-f5-fixture.log：`Executed 1 test, with 1 failure`），已按实测歧义修正。专属 UI 未运行，主机已验证打开与保存。

### F6：完成，a16aaed59
`App/Sources/Features/Reader/ReaderStyleStore.swift:86` 修改下划线字段写版本 1；`Packages/LegadoCore/Sources/LegadoCore/Reader/ReaderStyleArchive.swift:10` 导出必写版本 1。Android 下划线全局共享，iOS 仍按样式存储，未改模型。
红灯 r1-f6-red.log（testUnderlineEditsAndExportSetAndroidVersion）：`Executed 1 test, with 2 failures`；绿灯 r1-f6-green.log：`Executed 11 tests, with 0 failures`；r1-f6-ui.log：`Executed 1 test, with 0 failures`，补齐 B4a 旧日志 0 项的无效证据。

### F7：完成，5c756cc85
`App/Sources/Features/Reader/ReaderPresentationState.swift:41` 覆盖下一页时当前页左移、下一页静止，上一页左侧盖回；`App/Sources/Features/Reader/PageAnimation/ReaderPagePresentation.swift:75` 调整层级与移动页阴影，滑动不变。阈值仍为三分之一页或预测惯性，Android HorizontalPageDelegate 按最后移动方向判取消，保留此差异。
红灯 r1-f7-red.log（testCoverMovesCurrentPageOffStationaryNextPage）：`Executed 1 test, with 2 failures`；绿灯 r1-f7-green.log：`Executed 6 tests, with 0 failures`；r1-f7-ui.log：`Executed 1 test, with 0 failures`。

### F8：跳过，未完成，ee37b8d35
`App/Tests/LegadoUITests/ReaderContinuousUITests.swift:7` 新增面板截图明度对比，切换图标后及关闭重开后均未复现面板变化。r1-f8-red.log、r1-f8-red2.log 实际均为 `Executed 1 test, with 0 failures`，不能作为红灯；没有专用宿主修复，也未验证系统文件选择器与状态栏图标像素。保留根配色实现，后续需要可复现的操作路径或覆盖该通道的失败测试，不能宣称已修复。

### F9：完成，4e8cf29e9
`App/Sources/Features/Reader/ReaderPaperColor.swift:6` 纯色直接取背景，图片取缩略图平均像素并合成透明度；`App/Sources/Features/Reader/PageAnimation/SimulationPageTransition.swift:87` 纸背使用传入颜色。红灯前仅将旧白色常量提取为可测函数，保留旧行为。
红灯 r1-f9-red.log（testPaperBackUsesSolidOrAverageImageColor）：`Executed 1 test, with 3 failures`；绿灯 r1-f9-green6.log：`Executed 12 tests, with 0 failures`；r1-f9-f10-green-ui.log：`Executed 2 tests, with 0 failures`，其中仿真翻页 1 项。中间 green 至 green5 的色彩空间测试失败保留，未计通过。纸背平均色为缩略采样，与 Android 原图均值可能有细微差异。

### F10：完成，6dbfaf34c
`App/Sources/Features/Bookshelf/BookshelfView.swift:378` 按位添加、移除单个分组；`:408` 多选 Toggle 展示已有归属，保留其他分组。`Packages/LegadoCore/Tests/LegadoCoreTests/BookshelfCacheParityTests.swift:5` 覆盖 3→7→5 的位掩码变化。
红灯 r1-f10-red2.log（testAddingGroupPreservesExistingMemberships）：`Executed 1 test, with 1 failure`，添加后原 Sample Group 丢失；绿灯 r1-f10-green.log：`Executed 7 tests, with 0 failures`；r1-f9-f10-green-ui.log：`Executed 2 tests, with 0 failures`，其中分组 1 项。此前 red/UI 的重复元素定位失败不作业务红灯。

### F11：已证实并完成，c7531518e
`App/Sources/App/DatabaseLifecycleCoordinator.swift:52` 等所有进度写入释放后挂起；`App/Sources/Features/Reader/ReaderViewModel.swift:510` 后台保存先同步持有保护再排队；`App/Sources/Features/Reader/ReaderView.swift:252` 接入 UIKit 后台任务；`App/Sources/Features/Reader/ReaderDeviceController.swift:81` 保证任务结束释放。`ReaderTests.testDefaultProgressCoalescingActuallyWritesWithoutExplicitFlush` 等待真实默认 250ms 任务，未显式 flush。
红灯 r1-f11-red.log（testBackgroundTransitionDoesNotInterruptQueuedProgressSave）：`Executed 1 test, with 1 failure`，文件库读回 0 而非 872；绿灯 r1-f11-green2.log：`Executed 22 tests, with 0 failures`；r1-f11-f12.log 中 StartupUITests 为 `Executed 1 test, with 0 failures`，同日志另有 F12 红灯，整次运行不算全绿。

### F12：已证实并完成，1ccb673b6
`App/Sources/Features/Reader/PageAnimation/ScrollPageContainer.swift:78` 禁用仅阻止滚动手势，不再跳过内容更新与外部定位。`App/Tests/LegadoTests/ReaderScrollContainerTests.swift:8` 直接驱动真实 UIKit 容器，检查打开面板时高度、定位和关闭后位置。
红灯 r1-f11-f12.log 中 ReaderScrollContainerTests（testDisabledContainerReflowsAndKeepsExternalSeek）：`Executed 1 test, with 3 failures`；绿灯 r1-f12-green.log 中 LegadoTests 与 LegadoUITests 分别 `Executed 1 test, with 0 failures`，后一项验证整章连续滚动和跨章。未用静态扫描代替布局执行。

### F13：已证实并完成，242bc513b
`App/Sources/Features/Reader/ReaderBackgroundImageStore.swift:19` 共享同 URL/尺寸/文件版本的 UIImage 与在途解码，缓存预算 64MiB；`:38` 相册导入先降采样并应用方向后保存。`App/Sources/Features/Reader/ReaderInfoView.swift:94` 页面共用屏幕像素尺寸解码，`App/Sources/Features/Reader/ReaderInterfacePanel.swift:195` 缩略预览使用 512 像素；纸背复用同一结果。滚动仍为 VStack。
红灯 r1-f13-red.log（testBackgroundDecodeIsSharedAndBoundedAndImportIsDownsampled）：`Executed 1 test, with 4 failures`，现有解码路径提取后证实不同对象、4096 原图及导出未缩小。绿灯 r1-f13-green.log 中 LegadoTests、LegadoUITests 分别 `Executed 1 test, with 0 failures`。测试为真实 UIImage/ImageIO 解码与对象身份，未做真机内存峰值测量。

## 最终回归
从 ios 工作树根目录执行，无额外用户环境变量；完整命令与最终提交 SHA 写入 `.build/round6/r1-final-summary.md`。Core、App 使用任务书的 module cache/TMPDIR 与 swift test 参数；模拟器使用同一目标，完整 xcodebuild test 不含 only-testing。最终执行安排在最后提交之后，结果以 [最终回归摘要](../../.build/round6/r1-final-summary.md) 和 r1-final-core/app/ui.log 的实际 Executed 行为准，不把预检当最终证据。
预检 r1-preflight-core.log：`Executed 763 tests, with 0 failures`；r1-preflight-app.log：`Executed 368 tests, with 0 failures`，均早于最后提交，仅用于排查集成回归。旧 final-ui.log 早于旧出包提交，不能证明本次 R1；旧 dist 包也不包含 R1。F8 未完成，手机未安装或验收；没有需要用户批准的写操作，尚需补足 F8 复现证据与人工验收。

## 真机验收清单
安装前提：手机旧版标识为 com.starlitxiling.legado.ios，覆盖包须使用该标识及有效描述文件；不改 App/project.yml，不能直接安装默认标识包。
F1：恢复损坏或部分损坏阅读样式，进入阅读、选择并修改样式；阅读可用，加载回退不改变原阅读偏好，存储保留 broken 备份原文。
F2：书架按阅读时间排序，长按非首本置顶；该书排第一，全局与分组排序仍为阅读时间。
F3：订阅加号导入损坏 JSON，或用失效订阅源加载正文；显示中文操作名与原因。含 query 的书源 HTTP 错误不显示 query。
F4：启用自动换源，现有源返回服务器错误时只显示错误及手动换源；删除对应源后打开书籍才自动查找，手动换源会停止后台查找。
F5：恢复同一 Android 备份后打开原 24 本缺源书；13 本接回且重开保持，7 本歧义与 4 本无对应源仍提示缺源，手动选择所需源。
F6：界面面板修改下划线并关闭重开，设置保留；导出样式在 Android 导入，下划线不再因版本 0 重置。
F7：覆盖模式向左拖，当前页带右缘阴影移走、下一页静止；向右拖上一页从左盖回；短拖回弹，滑动模式保持原样。
F8（未完成）：切换深色状态栏图标，查看状态栏、目录、界面面板和系统文件选择器；若配色联动，请记录具体入口。
F9：设置深色纯色或背景图片，切到仿真翻页并慢拖；纸背随背景或图片平均色，不再固定白色。
F10：长按原属两个分组的书，分组菜单再勾一个；三个归属都保留，取消其中一个不影响另外两个。
F11：快速翻数页后立即回桌面，再返回或关闭重开书籍；停留位置应保留，后台写入期间不出现数据库错误。
F12：滚动模式读到章节中段，打开界面面板调整字号；关闭后应仍在原阅读文字附近，不能跳回错误页。
F13：导入高分辨率相册背景，连续滚动长章节并反复打开面板；图片清晰且无重复大图解码造成的持续内存增长，导出图最大边不超过导入时屏幕像素上限。
