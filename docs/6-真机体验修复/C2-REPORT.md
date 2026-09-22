# C2 长任务反馈

目录更新持有可取消 Task，默认显示总数与已处理数；书架和下载中心均有停止入口，即使用户关闭进度显示仍可停止。取消不生成错误或失败书籍，退出后可重新启动。取消时保留实际已处理数量，不把未启动项目算作完成。逐源搜索失败列表已在 A4c 实现。

翻页和朗读位置使用 250 ms 合并保存。显式保存、换章、重新载入、退出和阅读器进入后台会刷新最新位置，沿用串行数据库写入保证先后顺序。回归发现初始替换规则通知会触发相同规则的重复排版，现仅在规则实际变化后重排，保留跨章预览。

TDD c2-red.log：缺少停止与进度 API。c2-app2.log：356/0，新增可取消假 HTTP 请求的停止/重新启动，以及挂起保存计时器下的连续翻页合并、显式保存、退出刷新测试；旧默认值与恢复进度测试按新契约更新。c2-ui.log/xcresult：1/0，18 本假网络书架连续两次更新、显示进度、停止、无错误。无外网请求。

自行复审：父任务取消传播到更新任务；取消后才清理忙状态，避免更新并发；正在写入的阅读进度继续串行完成，退出等待写入后才同步。无子代理。

从 iOS worktree 根执行，无额外必填变量：

```sh
rtk proxy zsh -c 'CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/clang-cache" TMPDIR="$PWD/.build/tmp" swift test --package-path tools/appcore-check --cache-path "$PWD/.build/cache" --disable-sandbox --disable-automatic-resolution --skip-update > .build/round6/c2-app2.log 2>&1'
rtk proxy zsh -c 'CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache" xcodebuild -project App/Legado.xcodeproj -scheme Legado -destination "platform=iOS Simulator,id=AFAA07AC-5F79-4249-961C-06BE19C6086B" -derivedDataPath .build/startup-tests -resultBundlePath .build/round6/c2-ui.xcresult "-only-testing:LegadoUITests/BookshelfLayoutUITests/testChapterRefreshShowsProgressAndCanStopAndRestart" -collect-test-diagnostics never CODE_SIGNING_ALLOWED=NO test > .build/round6/c2-ui.log 2>&1'
```

末尾 `Executed 356 tests, with 0 failures`、`Executed 1 test, with 0 failures`、`TEST SUCCEEDED`。模拟器 ID 按本机替换，重跑需新结果目录。
