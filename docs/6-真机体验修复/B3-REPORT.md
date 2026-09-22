# B3 仿真与连续滚动

目标：仿真翻页接入系统交互；整章连续滚动，跨章保留位置；读取墨水屏翻页配置。全部在 iOS worktree 完成，固定 Kotlin 基线 2bdd3c58b，自行复审，未使用子代理。

仿真使用 UIPageViewController pageCurl、双面、相邻正反面 dataSource 与完成回调。交互取消时不提交阅读位置；完成后只提交一次。加载与程序翻页期间排队更新，避免抢占正在卷曲的页面。禁用系统点击翻页，统一由既有点击区域处理。非动画初始化只能提交一个可见页面；动画转场提交正反面，此差异已由模拟器异常定位并修复。

滚动改为整个章节与相邻章节的 UIScrollView，使用章节/页码稳定标识。滚动时仅同步可见位置，不再每页重置两屏；拖动和惯性期间保留前方内容，结束后裁剪为相邻章节窗口，按可见页和页内偏移重定位。未缓存的相邻章节显示可滚入的加载入口；加载时保留已有正文。墨水屏 pageAnimEInk 在界面选项、实际转场和图片排版中统一读取。

先红：原有两屏模式的整章断言失败；几何测试因缺少 ReaderScrollGeometry 编译失败，记录于 b3-red.log、b3-geometry-red.log。后续补全边界、空列表、跨章窗口重定位测试。App 346/0。

仿真 UI 验证章首越界不翻页、正向、反向与点击翻页；滚动 UI 验证整章超过两页、滚入第二章后反向滚动。原测试假设短距离卷曲一定取消，但 UIKit 的原生判定会完成短拖动，故测试改为验证真实系统交互和边界。手指中途反向后取消的手感仍由用户真机验收，未声称自动化覆盖该动作。

在 iOS worktree 根运行（不需要凭据），命令：

```sh
rtk proxy zsh -c 'CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/clang-cache" TMPDIR="$PWD/.build/tmp" swift test --package-path tools/appcore-check --cache-path "$PWD/.build/cache" --disable-sandbox --disable-automatic-resolution --skip-update > .build/round6/b3-app.log 2>&1'
rtk proxy zsh -c 'CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache" xcodebuild -project App/Legado.xcodeproj -scheme Legado -destination "platform=iOS Simulator,id=AFAA07AC-5F79-4249-961C-06BE19C6086B" -derivedDataPath .build/startup-tests -resultBundlePath .build/round6/b3-ui5.xcresult "-only-testing:LegadoUITests/ReaderContinuousUITests/testCurlTurnsBothDirectionsAndStopsAtChapterBoundary()" "-only-testing:LegadoUITests/ReaderContinuousUITests/testContinuousScrollContainsWholeChapterAndCrossesToNext()" -collect-test-diagnostics never CODE_SIGNING_ALLOWED=NO test > .build/round6/b3-ui5.log 2>&1'
```

末尾输出：App `Executed 346 tests, with 0 failures`。UI `Executed 2 tests, with 0 failures`、`TEST SUCCEEDED`。
