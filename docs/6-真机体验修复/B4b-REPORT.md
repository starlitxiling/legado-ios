# B4b 提示模板与状态栏

页眉/页脚左中右六个槽位均提供模板编辑、占位符追加、清空和恢复预设；编辑使用本地草稿，保存后统一持久化和重排，避免每键输入触发异步保存扰动光标。不再在选择信息类型时无条件把模板置 nil。

状态栏图标按日间、夜间、墨水屏独立配置。阅读器通过 PreferenceKey 将图标颜色传到全局主题承载层，正文保持自身颜色环境；退出阅读器撤销覆盖。初版局部 preferredColorScheme 被全局主题覆盖，已由截图发现并修正。最终截图白色时间、电池与 Wi-Fi 图标，浅色正文背景保持原样，页脚显示 Custom 1/4。

TDD：b4b-red.log 缺少 darkStatusIcons；单元验证日夜/墨水屏及六槽经数据库保存重载仍正确替换。App 350/0（b4b-app.log）；UI 1/0（b4b-ui3.log/xcresult）。模板初版逐键保存导致输入丢失，改为独立草稿编辑器后真实输入保存测试通过。自行复审完成。

从 iOS worktree 根执行，无凭据，完整命令同 B3-REPORT.md；App 日志 b4b-app.log，UI 日志和结果 b4b-ui3，方法过滤：

```text
-only-testing:LegadoUITests/ReaderContinuousUITests/testTemplateEditorAndStatusIconSetting()
```

末尾 `Executed 350 tests, with 0 failures`、`Executed 1 test, with 0 failures`、`TEST SUCCEEDED`。
