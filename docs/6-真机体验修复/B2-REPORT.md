# B2 阅读界面入口与内置背景

目标：一级面板可直接选择文字色、背景色和图片；内置背景、相册与文件入口齐全；样式缩略图、持久化、导出导入一致；新增样式与恢复预设布局。iOS worktree 实现，Android 固定 2bdd3c58b。

规格核验：固定基线 app/src/main/assets/bg 实际只有 14 张 JPG，非计划中的 24 张。已按原始字节与原名迁移全部 14 张到 LegadoCore Resources/ReaderBackgrounds，保留护眼漫绿、羊皮纸等 Android 名称引用，未虚构额外资源。ReadStyleDialog.kt 配置范围为 -10...40；面板按计划显示 -1.0...4.0，配置保留整数十分位。

实现：ReaderBackgroundResources 提供受限定的资源目录；ReaderSettings 统一 bgType=0/1/2 的颜色、内置、文件路径解析，并拒绝目录外符号链接。正文和圆点共用 ReaderBackgroundView。一级新增 ColorPicker 与背景图库；图库含 PhotosPicker 和文件入口。样式末尾新增加号，恢复预设布局保留当前颜色、图片与透明度，共用布局继续生效。

先红：负行距被归零、最大值仍为 50，两个断言失败（b2-red.log）。补全三种背景解析、资源全量读取、文件路径边界、恢复布局、存储重载、样式 ZIP 往返与新建选中行为。完整 Core 757/0、App 345/0。

UI 2/0：验证一级颜色入口、相册与文件入口、选择护眼漫绿、圆点引用、正文实际图片、终止进程重新启动后仍显示；回归原有边距与信息面板。截图已检查，图库与正文图片均正确。首次失败来自测试把“护眼漫绿”误写为“护眼淡绿”，修正为基线真实名字；符号链接测试改为真实存在的外部临时文件，避免 Foundation 对断链的解析差异。一次类过滤执行 0 项，未计入通过，改成带括号的具体方法过滤后执行 2 项。

在 iOS worktree 根运行，无需凭据，环境变量和 swift test 命令沿用 A4d-REPORT.md，日志为 .build/round6/b2-core-full.log、b2-app-final2.log。UI xcodebuild 过滤：

```text
-only-testing:LegadoUITests/ReaderBackgroundUITests/testPrimaryColorControlsBuiltInBackgroundAndStylePreview()
-only-testing:LegadoUITests/ReaderInterfaceUITests/testStylesMarginsAndTitleInformation()
```

结果 .build/round6/b2-ui3.xcresult、b2-ui3.log；末尾 `Executed 757 tests, with 0 failures`、`Executed 345 tests, with 0 failures`、`Executed 2 tests, with 0 failures`、`TEST SUCCEEDED`。

自行复审：核对所有资源与原始 Git blob 一致、颜色/图片三类路径、日夜/墨水屏字段、共享布局与透明度、创建和重置的持久化、原有 UI 流程。未使用子代理。下一步 B3，签名阻塞情况见 B1-REPORT.md。
