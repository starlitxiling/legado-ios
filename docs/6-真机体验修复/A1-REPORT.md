# A1 阅读样式兼容与回退

目标：修复恢复 Legado_Max 样式后阅读器被加载错误弹窗阻断的问题。范围为 ReadBookConfig、ReaderStyleStore、ReaderView，以及相关 Core/App/UI 测试和 DEBUG fixture；不修改真实备份与正式用户数据。

规格：主线仍固定 Kotlin 2bdd3c58b；兼容备份中颜色字符串及未知字段。计划中的 #FF63C37D 十进制转换有误，按 UInt32 位值转 Int32 得 -10239107，不能使用 -10534531。

实现：六个 Int 颜色字段接受 #RRGGBB/#AARRGGBB/十进制字符串，无效值回默认；顶层样式数组逐项解码，失败项保留索引并回退对应预设，全失败抛出含字段路径的错误。内置预设独立严格解码，避免回退递归。自动加载损坏 readConfig/shareReadConfig 时写入 AppLogStore 并回退，不覆盖损坏原始数据；ReaderView 自动加载异常只记日志，继续排版。主动导入/导出操作仍能提示错误。

验证：先跑红测试，Core 新增三项均失败，App 损坏配置用例失败；修复后专项 Core 6/0、App 7/0，全量 Core 750/0、App 323/0。XCUITest testDamagedStylesDoNotBlockReadingOrStylePanel 1/0，截图 a1-style-fallback 保存在 a1-ui.xcresult。UI 构建成功。

命令均在 iOS worktree 根执行，Swift 测试使用仓库内缓存变量：

```bash
rtk proxy env CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/clang-cache" TMPDIR="$PWD/.build/tmp" swift test --package-path Packages/LegadoCore --cache-path "$PWD/.build/cache" --disable-sandbox --disable-automatic-resolution --skip-update
rtk proxy env CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/clang-cache" TMPDIR="$PWD/.build/tmp" swift test --package-path tools/appcore-check --cache-path "$PWD/.build/cache" --disable-sandbox --disable-automatic-resolution --skip-update
rtk proxy xcodebuild -project App/Legado.xcodeproj -scheme Legado -destination 'platform=iOS Simulator,name=Legado-Startup-Check' -derivedDataPath .build/startup-tests '-only-testing:LegadoUITests/ReaderInterfaceUITests/testDamagedStylesDoNotBlockReadingOrStylePanel()' -collect-test-diagnostics never CODE_SIGNING_ALLOWED=NO test
```

日志位于 `.build/round6/a1-{core-red,app-red,core-green,app-green,core-full,app-full,ui}.log`。全量末尾：`Executed 750 tests, with 0 failures`、`Executed 323 tests, with 0 failures`；UI：`Executed 1 test, with 0 failures`、`TEST SUCCEEDED`。

自行复审已检查：损坏元素不拖垮其它样式、默认样式解码无递归、导入导出仍往返、失败配置未被静默覆盖、未知 BookSource.nextPageLazyLoad 忽略。用户禁止子代理，因此未执行计划中的 opus-explorer 交叉复审，不将自行复审冒充独立审查。真机包在阶段 A 完成后统一交付，当前未覆盖安装此修复。
