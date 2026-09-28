# C3 平台杂项

补充 NSLocalNetworkUsageDescription，并同步 project.yml 与生成的 Info.plist。前台定时任务由 scenePhase 与开关变化启动/取消；同一状态重复通知不新增循环，重新启动先等待旧任务退出，避免并行执行。视图退出取消任务。

书架、搜索、书源、目录和设置列表使用语义字号；书名允许两行，书源状态行允许自适应高度。最大辅助字号截图复审发现书架图标占位仍固定为 18 pt，已改 ScaledMetric 跟随文字缩放。删除未启用 MCP 开关。

TDD c3-red.log 缺少前台循环模型。c3-app.log：358/0，包括首次进入前台、重复事件去重、后台取消、再次激活、开关关闭与局域网用途声明。c3-ui.log/xcresult：2/0，验证辅助字号书架行高度实际增大、四个文字标签、移除 MCP 占位和前后台切换后的导航。修正图标间距后 final-ui 首项再次通过，最终 7 项回归全部通过，记录见 FINAL-REPORT.md。自行复审，无子代理。

从 iOS worktree 根执行，无额外必填变量：

```sh
rtk proxy zsh -c 'CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/clang-cache" TMPDIR="$PWD/.build/tmp" swift test --package-path tools/appcore-check --cache-path "$PWD/.build/cache" --disable-sandbox --disable-automatic-resolution --skip-update > .build/round6/c3-app.log 2>&1'
rtk proxy zsh -c 'CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache" xcodebuild -project App/Legado.xcodeproj -scheme Legado -destination "platform=iOS Simulator,id=AFAA07AC-5F79-4249-961C-06BE19C6086B" -derivedDataPath .build/startup-tests -resultBundlePath .build/round6/c3-ui.xcresult "-only-testing:LegadoUITests/BookshelfLayoutUITests/testBookshelfRowsGrowWithAccessibilityTextSize" "-only-testing:LegadoUITests/StartupUITests/testLabeledTabsAndSettingsRemainUsableAfterForegrounding" -collect-test-diagnostics never CODE_SIGNING_ALLOWED=NO test > .build/round6/c3-ui.log 2>&1'
```

末尾 `Executed 358 tests, with 0 failures`、`Executed 2 tests, with 0 failures`、`TEST SUCCEEDED`。模拟器 ID 按本机替换，重跑需新结果目录。实际局域网系统授权与真机字体体验留待连接设备后验收。
