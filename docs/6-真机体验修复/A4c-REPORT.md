# A4c 书源与发现搜索错误语义

目标：搜索失败可定位到具体书源，无书源时可直接进入导入入口；书源导入、编辑、登录、校验和发现错误带操作与对象上下文。

实现：Sources/ReplaceRules 的 perform 在每个调用处指定操作与书源名、URL、分组或批量数量；编辑、导入、Cookie、二维码与登录使用 UserFacingError。发现区分书源操作、分类和书籍列表加载。SourceChecker 支持宿主错误格式化，将中文原因存入带源名与 URL 的校验结果。取消不会成为校验失败提示。

搜索保留逐源结构化失败信息，列表可展开显示源名、URL 与原因；最多 500 条，每条正文限制 2048 字。取消源不计入失败数。没有任何书源时提示“请先导入书源”并提供导航入口；已有书源但当前范围无启用项时提示启用或调整范围。既有搜索结果、范围、过滤与历史行为保留。

先红：无书源提示与中文超时两项新测试失败（a4c-red.log）。修复后专项 57/0，完整 Core 755/0、App 337/0；新增取消源不列为失败、校验中文消息和源标识持久化测试。模拟器 SearchInterfaceUITests 4/0，覆盖无书源导航、展开超时详情，并回归搜索过滤、范围持久化与历史删除。

命令在 iOS worktree 根执行，缓存变量、完整 swift test 与 xcodebuild 命令沿用 A1-REPORT.md；专项过滤 --filter SearchErrorPresentationTests，UI 过滤：

```text
-only-testing:LegadoUITests/SearchInterfaceUITests
```

原始末尾：`Executed 755 tests, with 0 failures`；`Executed 337 tests, with 0 failures`；`Executed 4 tests, with 0 failures`、`TEST SUCCEEDED`。日志 .build/round6/a4c-{core-full,app-full,ui}.log，截图 a4c-search-failures 在 a4c-ui.xcresult。迁移清单减少 35 行，140 -> 105；本批仅剩明确日志使用 localizedDescription。

自行复审：核对各批量操作标题、错误与成功状态的区分、源 URL 与名称保留、取消不进入失败详情、上限约束、0 书源与范围无可用源区分。没有使用真实网络凭据或部署真机；继续 A4d。
