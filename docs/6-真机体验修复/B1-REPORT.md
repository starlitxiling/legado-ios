# B1 覆盖与滑动手势

目标：覆盖、滑动模式实时跟随手指，三页布局支持前后方向，低于阈值回弹，章首章尾沿用现有跨章加载。工作目录为 iOS worktree；对照固定 2bdd3c58b 的 HorizontalPageDelegate.kt、CoverPageDelegate.kt 和 SlidePageDelegate.kt。

实现：ReaderPagePresentation 的水平容器使用 DragGesture，上一页、当前页、下一页由偏移状态驱动；覆盖模式邻页从对应侧压入，滑动模式当前页同步移动。完成阈值为页面宽度三分之一，快速滑动通过预测距离判定；无相邻页只产生轻微阻尼且不提交。动画完成才提交一次翻页，页码变更无动画复位，退出取消待提交任务。ReaderInputView 在这两种模式中关闭旧水平翻页触发，保留点击、长按、书签与鼠标滚轮。模型记录翻页方向；跨章保留上一章布局，并对直接打开章节按缓存和预下载设置准备上一章预览，取消和布局版本检查阻止旧预览回写。

规格说明：计划“宽度三分之一触发”和“半屏回弹”矛盾，采用明确的三分之一触发规则；UI 用五分之一宽度慢拖验证回弹。Android 覆盖绘制细节与计划描述不同，本实现按计划要求让下一页从右侧盖入、上一页从左侧盖入。

先红：真实 Reader UI 慢拖约五分之一屏，原实现从第 1 页变为第 2 页，断言失败，证据 .build/round6/b1-red.log、b1-red.xcresult。修复后两种模式均验证回弹、前翻与回退；原有跨章测试增加上一章预览断言。拖动决策测试覆盖阈值、速度预测、反向惯性、边界、非法数值及三页偏移。

验证：App 全量 342/0（b1-app-full.log）；ReaderInterfaceUITests 全量 9/0（b1-ui-full.log、b1-ui-full.xcresult），包含双页翻页、点击书签、选择文本、缺源返回、图片和样式面板。截图 b1-drag-mode-0/1 已查看，无残留偏移。无 Core 行为修改，本单元不重复 Core 全量。

在 iOS worktree 根运行，缓存环境变量沿用 A4d-REPORT.md：

```sh
rtk proxy zsh -c 'CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/clang-cache" TMPDIR="$PWD/.build/tmp" swift test --package-path tools/appcore-check --cache-path "$PWD/.build/cache" --disable-sandbox --disable-automatic-resolution --skip-update > .build/round6/b1-app-full.log 2>&1'
```

UI xcodebuild 过滤 `-only-testing:LegadoUITests/ReaderInterfaceUITests`。原始末尾：`Executed 342 tests, with 0 failures`；`Executed 9 tests, with 0 failures`；`TEST SUCCEEDED`。

自行复审：核对拖动与旧识别器不重复提交、双页边界、回退预览、布局失效与退出取消；未启动子代理。手指跟随的最终手感仍由用户真机体验确认。

阶段 A Release 已构建：dist/Legado-1.0-a4e1f3c76.ipa，8553937 字节。沿用既有应用标识准备覆盖更新，但签名仍返回 errSecInternalComponent，尚未安装。构建日志 .build/round6/phase-a-release.log；签名脚本 .build/round6/sign-iphone-app.sh。开发继续阶段 B，不把签名失败标记为安装完成。
