# A4b 阅读链路错误语义

目标：正文、目录、朗读、漫画、音频以及阅读器工具中的失败能说明操作、对象与下一步，取消不显示为错误。

实现：ReaderViewModel 使用 UserFacingError，按正文加载、自动换源、排版、目录、进度、批注、书签、WebDAV 与正文编辑分别构造提示；书名、章节、书源加入上下文，正文错误提供重试、换源、书源管理、返回。预加载错误独立保存。ReaderView 使用统一 errorBanner，后台换源进度移至底部，避免遮住提示动作。主动操作的样式、目录、字体、备忘录、字典、段评、高亮与脚本错误分别带操作语义。

Toc、MediaBookLibrary、MangaReaderModel 与 ReadAloudController 改为结构化错误，保留只读文字投影以兼容现有视图与调用方。朗读和音频核心引擎新增宿主错误格式化入口，App 注入中文提示，返回 nil 可抑制取消；保留默认行为与核心包独立性。目录保存的数据库原始错误留在 AppLogStore，用户提示显示操作与数据库代码，不暴露 SQL。

先红：断网正文测试缺少中文操作、书名、章节、网络说明，共 4 处失败（a4b-red.log）。修复后全量 Core 754/0（a4b-core-full.log），App 334/0（a4b-app-full2.log）。数据库回滚测试保留全部书籍、章节、进度断言，另验证中文提示和日志中的原始注入错误；朗读测试验证格式化与取消抑制。

模拟器：ReaderInterfaceUITests 全组 8/0（a4b-ui.log）；ErrorPresentationUITests 4/0（a4b-ui2.log、a4b-ui2.xcresult），包括断网正文的书名章节及动作、换源失败的候选源名、目录刷新重试与关闭、中文文件选择器。首轮断网测试页漏注入 AppContainer 导致仅 DEBUG 页面崩溃，补充依赖后复测通过。

命令在 iOS worktree 根执行，缓存变量、swift test 全量命令及 xcodebuild 工程与模拟器设置沿用 A1-REPORT.md。UI 过滤：

```text
-only-testing:LegadoUITests/ReaderInterfaceUITests
-only-testing:LegadoUITests/ErrorPresentationUITests
```

原始末尾：`Executed 754 tests, with 0 failures`；`Executed 334 tests, with 0 failures`；两组 UI 分别 `Executed 8 tests, with 0 failures` 和 `Executed 4 tests, with 0 failures`。允许清单从 203 行减为 140 行；本批 63 行全部迁移，Reader 剩余 localizedDescription 仅用于明确的日志。

自行复审：逐个核对动作与重试目标，非正文操作不误触发正文重试；检查取消过滤、旧请求守卫、后台错误不覆盖前台错误、书籍对象标识、恢复提示与数据库回滚。未启动子代理，未安装本轮真机包。继续 A4c/A4d 后交付阶段 A。
