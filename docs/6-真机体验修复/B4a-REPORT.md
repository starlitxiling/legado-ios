# B4a 下划线

补齐关闭、实线、虚线、点线、双线、波浪线、双虚线，正文/标题独立开关、颜色、宽度、距基线。CoreText 绘制排除图片占位；宽度 0...10、距离 0...30 对齐固定 Kotlin 基线 2bdd3c58b TextLine.kt 和 ReadBookConfig.kt。

先红 b4a-red.log 缺失绘制器。暂停恢复后检查截图发现每个 CoreText run 重置虚线；新增位图等价测试 b4a-review-red.log 失败，合并相邻同色线段后通过。六种线型的位图各不相同，禁用正文/标题均不绘制。

验证：App 全量 348/0（b4a-final.log）；模拟器 1/0（b4a-ui3.log/xcresult），界面选择双虚线、调节线宽、关闭面板后重新打开仍保持。已检查实际正文截图。自行复审完成，未使用子代理。

命令在 iOS worktree 根执行，无凭据。沿用 B3-REPORT.md 的完整命令，App 日志改为 b4a-final.log，UI 日志及结果改为 b4a-ui3，过滤为：

```text
-only-testing:LegadoUITests/ReaderContinuousUITests/testUnderlineOptionsPersistAfterClosingPanel()
```

末尾：`Executed 348 tests, with 0 failures`、`Executed 1 test, with 0 failures`、`TEST SUCCEEDED`。
