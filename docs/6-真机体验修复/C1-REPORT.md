# C1 书架性能与交互

封面使用 URL 与来源上下文作缓存键，actor 内通过 ImageIO 按格子像素尺寸降采样，主线程只创建 UIImage 包装。移除 Book JSON task identity；本地图片文件读取也移至后台。缓存容量为 0 时不复用缓存，仍降采样。

书籍长按菜单提供置顶、移出确认、分组和详情。空书架提供导入书源和本地书入口，标签栏显示文字。快速定位最多 20 个均匀分段入口，保留首尾；500 本书 UI fixture 可跳到最后一本。

TDD：c1-red2.log 缺失缓存 API/分段索引；c1-app.log 最终 354/0，覆盖 1600x2400 图片降采样、URL 命中、大小区分、禁用缓存和 10000 本索引上限。自行复审完成，无子代理。

模拟器：c1-ui2 中菜单/500 本定位、文件夹详情两项通过；空书架测试误用页面标题“书源管理”，按实际“书源”修正后 c1-ui3 1/0。首次 c1-ui 发现模拟器使用旧测试 runner，卸载测试 runner 后验证新二进制，后续以实际执行数量为准。

从 iOS worktree 根运行，无额外必填环境变量：

```sh
rtk proxy zsh -c 'CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/clang-cache" TMPDIR="$PWD/.build/tmp" swift test --package-path tools/appcore-check --cache-path "$PWD/.build/cache" --disable-sandbox --disable-automatic-resolution --skip-update > .build/round6/c1-app.log 2>&1'
rtk proxy zsh -c 'CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache" xcodebuild -project App/Legado.xcodeproj -scheme Legado -destination "platform=iOS Simulator,id=AFAA07AC-5F79-4249-961C-06BE19C6086B" -derivedDataPath .build/startup-tests -resultBundlePath .build/round6/c1-ui3.xcresult "-only-testing:LegadoUITests/BookshelfLayoutUITests/testEmptyShelfHasSourceAndLocalImportActions" -collect-test-diagnostics never CODE_SIGNING_ALLOWED=NO test > .build/round6/c1-ui3.log 2>&1'
```

末尾 `Executed 354 tests, with 0 failures`、`Executed 1 test, with 0 failures`、`TEST SUCCEEDED`。模拟器 ID 可替换为本机设备，重新执行时使用新的结果目录。实际 iPhone 滚动手感仍由用户验收。

## 2026-09-28 最终复审修正

空书架引导按书籍总量判断，覆盖有内置分组的空文件夹模式。置顶时将当前独立排序分组切换为手动排序，防止分组名称排序覆盖全局排序。UI fixture 使用独立名称排序；最终 c1-review-green 2/0，验证第二本置顶后实际顺序、移出确认只删除该书、空文件夹模式两项导入入口。

c1-review-red2 复现空文件夹缺入口；置顶测试最初被横向分组按钮不可点击阻断，改走已验证的文件夹导航后验证实际置顶行为。未将测试控件定位失败当作业务红灯。

运行命令沿用本文 xcodebuild 模板，结果/日志名 c1-review-green，过滤 `BookshelfLayoutUITests/testPinOverridesGroupSortAndRemovalKeepsOtherBooks` 与 `BookshelfLayoutUITests/testEmptyFolderShelfShowsImportActions`。末尾 `Executed 2 tests, with 0 failures`、`TEST SUCCEEDED`。
