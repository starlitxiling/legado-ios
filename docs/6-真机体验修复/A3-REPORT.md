# A3 取消错误与书架状态

目标：取消的读库任务不再显示系统错误，且启动分组不再在 await 后改变 task(id:) 造成自身取消。范围：ErrorPresentation、BookshelfView/Model、DEBUG gallery、相关逻辑与 UI 测试。

实现：识别 CancellationError、NSError 桥、URLError.cancelled、GRDB SQLITE_INTERRUPT 及 NSUnderlyingErrorKey 包装，递归有循环/深度边界。未把一般 SQLITE_ABORT、数据库损坏或网络超时视为取消。四个书架动作 catch 和 ViewModel 均过滤取消，成功刷新清除旧动作错误；更新动作失败立即返回，避免后续刷新把真正失败立即抹掉。初始分组在 View 初始化时确定。

测试：注入 CancellationError 的书架读取，修复前 errorMessage 非空导致失败；修复后专项 5/0，全量 App 325/0。模拟器两个场景通过：取消读取不出现错误，随后切文件夹并进入分组恢复书籍列表；既有文件夹导航/长按详情继续通过。日志 `.build/round6/a3-red.log`、`a3-green.log`、`a3-app-full.log`、`a3-ui.log`，结果包 `a3-ui.xcresult`。

命令：在 iOS worktree 根，使用 A1-REPORT.md 同一组缓存环境变量执行 swift test --package-path tools/appcore-check；专项加 --filter BookshelfLayoutTests。模拟器在同一工程/模拟器执行以下两个 only-testing 过滤：

```text
LegadoUITests/BookshelfLayoutUITests/testCancelledReadDoesNotShowErrorAndGroupChangeRecovers()
LegadoUITests/BookshelfLayoutUITests/testFolderNavigationAndLongPressDetail()
```

原始末尾：`Executed 325 tests, with 0 failures`；UI `Executed 2 tests, with 0 failures`、`TEST SUCCEEDED`。自行复审检查了取消与真实失败区分、旧任务覆盖新任务的 generation 守卫、真实动作失败不会立即被清空。无代理交叉复审；阶段 A 完成后统一真机交付。
