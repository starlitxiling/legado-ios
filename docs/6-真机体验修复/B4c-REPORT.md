# B4c 样式导入分享与段评图标

新增 HTTP/HTTPS JSON/ZIP 网络导入，响应上限 16 MB，使用既有有界 HTTP 客户端。失败保留当前样式并显示带地址的中文错误。新增 ShareLink ZIP 文件分享，文件导出成功后也显示分享入口。

段评图标提供默认图标、两套 SVG 模板、自定义模板命名保存/去重/删除、50...200% 缩放、颜色与正文色回退。保留 Android {{count}} 占位符、最多 999、宽高比上限 4。界面预览、阅读菜单段评入口和段评列表使用同一图标视图。静态 SVG 通过无脚本、无持久数据的 WebKit 图像蒙版显示；CSP 禁止网络，XML 校验拒绝脚本/外部引用/实体，大小上限 64 KB；不新增依赖。

TDD：b4c-red.log 缺少网络导入入口与 SVG 模型。App 352/0（b4c-app2.log），验证 JSON 与 ZIP 假网络导入、404/错误协议不更改选择、SVG 解析和数量替换、模板去重。UI 1/0（b4c-ui5.log/xcresult），验证坏地址中文提示、气泡 SVG 真实预览、缩放、系统 ActivityListView 与“保存到文件”入口。截图已检查。自行复审完成，无子代理，无实际上传。

命令从 iOS worktree 根执行，完整形式同 B3-REPORT.md；App 日志 b4c-app2.log，UI 日志/结果 b4c-ui5，过滤如下（此 Xcode 新增方法的括号过滤曾执行 0 项，实际以无括号运行 1 项为准）：

```text
-only-testing:LegadoUITests/ReaderContinuousUITests/testStyleNetworkImportValidationSharingAndReviewIcon
```

末尾 `Executed 352 tests, with 0 failures`、`Executed 1 test, with 0 failures`、`TEST SUCCEEDED`。
