<subagent_contract>
你是一个子代理。你的最后一条消息是唯一交付物，调用方看不到其他任何内容。必须遵守：
1. 所有发现、结论、文件路径都写进最后一条消息；禁止以计划、提问或"接下来我会…"收尾——先做完，再汇报。
2. 第一段先给结论（哪些单元完成、哪些未完成及原因），细节放后面。
3. 涉及代码的每条论断都带 `文件路径:行号` 引用。
4. 如实汇报：测试失败就原样贴失败输出末尾；跳过的步骤要说明；没验证过的事不得声称完成；不确定就标注"未验证"。
5. 只做指派的任务：不扩 scope、不顺手重构、不 push。
6. 改代码时贴合周边代码风格；注释只写代码本身无法表达的约束，不写解释本次改动的注释。
7. 用完整句子；禁止碎片化短语、箭头链、自造缩写、表情符号。
8. 某个单元被卡住就跳过它继续做下一个，并在报告里精确说明缺什么信息；不许猜测、不许编造。
9. 关键假设失效（任务书写的现象在代码里不成立、或与 Kotlin 实际不符）立即记录并跳过该单元，不要硬做。
</subagent_contract>

<task>
目标：轮次 6 返修 R1。修复独立复审（`docs/6-真机体验修复/REVIEW.md`）确认的 P1 与主要 P2 缺陷，并补齐此前不成立的验证证据，最后重新跑完整回归。

工作目录：/Users/xiling/Work/legado-ios/.claude/worktrees/ios（分支 `ios`，起点 `8235d2fe2`）。
Kotlin 规格（只读，固定基线，不要切分支）：/Users/xiling/Work/legado-ios/app/src/main/java/io/legado/app/ ，下文简写为 `K/`。
Swift 阅读器目录简写为 `R/` = `App/Sources/Features/Reader/`。

## 背景（已由独立复审与主会话核实，不要推翻）

- 上一轮由单个会话实现并自审，本次复审发现若干缺陷；标注「存疑」的单元需要先写失败测试证实现象，证实不了就在报告里说明并跳过，不要凭推测改。
- 用户手机为分叉 Legado_Max，备份样本 `.build/fixtures-local/real-backup.zip`（gitignored，禁止提交或复制进受版本控制目录）。
- 24 本缺源书：备份的 4198 个书源即全部，iOS 导入无丢失；其中 20 本的 origin 与某书源 bookSourceUrl 仅差尾部斜杠、首尾空白或 `#…` 后缀，4 本完全无对应源。
- 此前两处证据无效：`B4a-REPORT.md` 声称的 `b4a-ui3` 实际 `Executed 0 tests`；`final-ui.log`（11:20）早于出包提交 `794cc4077`（11:26）。本轮所有 UI 证据必须核对日志里的实际执行数。

## 单元（按顺序做；每个单元独立 TDD 先红后绿，完成即单独 commit，message 以 `[round 6 R1-Fx]` 开头，末尾附 `Co-Authored-By: Codex <noreply@openai.com>`；某单元失败不影响继续做后面的单元）

**F1 [P1] 样式回退不得覆盖用户原文件**
- 现象：`R/ReaderStyleStore.swift:32-46` 解码失败时只在内存换成预设；之后 `persist()`（`:175-183`）会把预设写回 `readConfig.json` / `shareReadConfig.json`，`synchronizeSettings()`（`:186-192`）也立刻改写 UserDefaults 阅读设置。
- 期望：进入回退状态时先把原始内容另存为 `readConfig.broken-<时间戳>.json`（同一存储位置，不覆盖已有备份），之后才允许写入；回退时不改写 UserDefaults 阅读设置。部分条目损坏时（`ReadBookConfig.swift:286`、`ReaderStyleStore.swift:120`）同样保留原文备份。
- 测试：塞入损坏 JSON，load 后执行一次选择样式与一次修改样式，断言原始字节在备份文件中完整保留。

**F2 [P1] 置顶不得修改排序设置**
- 现象：`App/Sources/Features/Bookshelf/BookshelfView.swift:403-410` 置顶时把分组 `bookSort` 与全局 `bookshelfSort` 永久改成手动。
- 期望：对齐 `K/ui/book/info/BookInfoViewModel.kt:486-494`：`order = minOrder - 1`，`durChapterTime = 当前时间`，不动任何排序设置。
- 测试：按阅读时间排序下置顶一本，断言排序设置未变且该书排第一；已有的置顶 UI 测试按新语义调整（点击后等待元素而非立即比较 frame）。

**F3 [P1] Rss 与 Browser 错误展示走统一通道，守门测试补漏**
- 现象：`App/Sources` 下 `String(describing: error)` / `String(describing: failure)` 共 19 处，其中 18 处写进界面状态（`Features/Rss/RssViewModels.swift:18,28,58,84,90,118,150,157`、`RssReadView.swift:105-129`、`RssSourceEditView.swift:50,65`、`RssFavoritesView.swift:20,34`、`RssSourceListView.swift:41`、`Browser/BrowserInteraction.swift:83`），会显示英文 case 名与含 query 的完整 URL。
- 期望：改用 `App/Sources/Shared/ErrorPresentation.swift` 的 `presentation(operation:)`，给出操作名；`BookshelfView.swift:254` 的日志用法保留。
- 守门测试 `tools/appcore-check/Tests/BookshelfAdvancedCheckTests/ErrorPresentationTests.swift:47-51`：把 `String(describing: error|failure)` 与字符串插值 `"\(error)"` 纳入扫描；豁免只按「整条语句是日志调用」判断，不再按整行含 `NSLog(` 豁免。允许清单保持为 0。
- 同时：`WebBookError.httpStatus` 的用户文案（`Packages/LegadoCore/Sources/LegadoCore/LocalizedErrors.swift:11` 附近）只显示 host 与路径，不显示 query；`PaginationError`（`R/Paginator.swift:54`）实现中文 `LocalizedError`。

**F4 [P2] 自动换源只在书源不存在时触发；取消判定收窄**
- 现象：`R/ReaderViewModel.swift:212,355-356` 任何非取消、非锁章的加载失败都启动后台换源，成功后永久迁移书源。Android 只在「非本地书且书源不存在」时自动换源（`K/ui/book/read/ReadBookViewModel.kt:192-195`）。
- 期望：仅书源不存在（`ReaderError.missingSource` 或查不到 origin 对应书源）时自动换源；其他失败只显示错误条及手动「换源」动作。菜单里的手动换源（`R/ReaderMenuView.swift:37,41`）启动前取消在途的后台换源。
- `ErrorPresentation.swift:13`：`URLError.cancelled` 不再无条件算取消。查看 `Packages/LegadoCore/Sources/LegadoCore/Network/HTTPSessionPool.swift:92,102,107` 在 TLS 校验失败、代理认证失败、会话失效时如何产生 `.cancelled`，让这些路径抛出可区分的错误（例如在该处改抛带原因的专用错误），使用户看得到「证书校验失败」等提示；真正的任务取消仍视为取消。
- 测试：书源存在但返回 5xx 时不触发换源；书源不存在时触发；TLS 失败路径产出非取消错误。

**F5 [P2，用户已决定要做] 书源网址规范化匹配**
- 打开书籍、查书源时，精确匹配失败后再按规范化规则匹配一次：去首尾空白、去尾部 `/`、忽略 `#` 及其后缀、scheme 与 host 小写。命中唯一书源时把书的 `origin` 改写为该书源的 `bookSourceUrl` 并保存；命中多个时不自动改挂，按缺源处理。
- 测试：用构造数据覆盖尾部斜杠、尾部空格、`#yc1101b` 后缀、多重命中四种情况；再用 `real-backup.zip` 离线跑一遍（写入临时目录，不入库），报告 24 本里有几本被接回。

**F6 [P2] 下划线导出与 Android 兼容**
- 现象：iOS 从不写 `underlineConfigVersion = 1`（仅 `Packages/LegadoCore/Sources/LegadoCore/Reader/ReadBookConfig.swift:50,135,221`），Android 读到 0 会重置下划线设置（`K/help/config/ReadBookConfig.kt:110-123`）。
- 期望：用户修改过下划线设置或导出样式时写 1；导出后再解码断言字段为 1。另外在报告里说明 Android 下划线是全局共享、iOS 按样式存储这一差异，不改存储模型。

**F7 [P2] 覆盖翻页方向对齐 Android**
- 现象：`R/ReaderPresentationState.swift:37-46` 覆盖模式下一页从右侧盖入，当前页不动。Android（`K/ui/book/read/page/delegate/CoverPageDelegate.kt:42-51`）是当前页向左移走、露出下面静止的下一页，移动页边缘带阴影；上一页则是上一页从左侧盖回。
- 期望：按 Android 改覆盖模式偏移与层级，加边缘阴影；滑动模式不动。翻页阈值保持现状，在报告里说明与 `HorizontalPageDelegate.kt:124` 的差异即可。
- 测试：单元测试断言 `offsets(slide: false)` 在向后与向前拖动时的三页偏移符合上述模型。

**F8 [P2] 状态栏图标开关只影响状态栏**
- 现象：`App/Sources/Shared/Theme/ThemeEnvironmentModifier.swift:26` 用它驱动根视图 `preferredColorScheme`，面板、目录、系统文件选择器都跟着变。
- 期望：只影响阅读器的状态栏样式（例如阅读器宿主控制器的 `preferredStatusBarStyle`）。

**F9 [P2] 仿真翻页纸背颜色**
- `R/PageAnimation/SimulationPageTransition.swift:86` 纸背固定白色；改为当前页背景色（纯色背景取该色，图片背景取平均色，参照 `K/ui/book/read/page/delegate/SimulationPageDelegate.kt:325` 的 `bgMeanColor`）。

**F10 [P2] 分组改为多选**
- `BookshelfView.swift:378-383,415-419` 单选会覆盖原有多个分组；改成多选（位掩码按位增删），对齐 Android `GroupSelectDialog`。测试：书原属两个分组，再加一个后三个都在。

**F11 [P2，存疑] 进后台时阅读进度可靠落盘**
- `R/ReaderView.swift:278-279` 在 inactive 时写进度，没有 `beginBackgroundTask` 保护；`App/Sources/App/DatabaseLifecycleCoordinator.swift:42-47` 进后台时挂起 GRDB，可能打断写入。
- 期望：写进度期间持有后台任务，挂起数据库前等待在途的进度写入完成；补一条让 250 ms 合并写入真实执行的单元测试（现有 `ReaderTests` 注入 3600 秒，从未覆盖这条路径）。

**F12 [P1，存疑] 滚动模式面板打开时的刷新与定位**
- `R/PageAnimation/ScrollPageContainer.swift:75-78` 在 `enabled == false` 时先写 `value` 再 return，导致面板打开时改字号不刷新，关闭后 `externalSeek` 判为假、定位到错误页。先写 UI 或单元测试证实；证实则修复，使面板打开时实时重排并保持阅读位置。

**F13 [P1，存疑] 背景图解码内存**
- `R/ReaderInfoView.swift:88-97`、`R/ReaderView.swift:542`、`R/ReaderInterfacePanel.swift:214` 每页各自读取并解码背景图，相册图按原分辨率存储。改为按样式共享一份、按屏幕像素降采样的解码结果；相册导入时降采样后再存。滚动模式容器不要改成 Lazy 布局（会破坏现有滚动几何），只解决重复解码。

## 约束
- 不改公共数据模型的存储格式（F5 改写单本书的 origin 除外），不加新依赖，不 push，不访问真实 WebDAV 写接口，不改 `App/project.yml` 的包标识。
- 新增 App 源文件后运行 `xcodegen generate` 并一起提交生成物；新增 appcore-check 源链接后 touch 其 `Package.swift`。
- 所有 shell 命令加 `rtk proxy` 前缀（与上一轮报告一致）。

## 验证要求（命令从工作目录根执行）
- Core：`rtk proxy zsh -c 'CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/clang-cache" TMPDIR="$PWD/.build/tmp" swift test --package-path Packages/LegadoCore --cache-path "$PWD/.build/cache" --disable-sandbox --disable-automatic-resolution --skip-update > .build/round6/r1-core.log 2>&1'`
- App：同上，把 `--package-path` 换成 `tools/appcore-check`，日志 `.build/round6/r1-app.log`。
- UI：`xcodebuild -project App/Legado.xcodeproj -scheme Legado -destination "platform=iOS Simulator,id=AFAA07AC-5F79-4249-961C-06BE19C6086B" -derivedDataPath .build/startup-tests -resultBundlePath .build/round6/r1-<单元>.xcresult "-only-testing:LegadoUITests/<类>/<方法>()" test`，完整参数参照 `docs/6-真机体验修复/C3-REPORT.md:13`。每次都 grep 日志中的 `Executed N tests`，N 为 0 视为未验证。
- 全部单元完成后：跑一次不带 `-only-testing` 的完整 `LegadoUITests` 回归，与 Core、App 全量一起，**必须在最后一个提交之后运行**，日志 `.build/round6/r1-final-*.log`。
- 如沙箱阻止 xcodebuild 或模拟器：跳过这一步但**不要停下**，继续把全部单元的代码与可运行的 Core、App 单元测试做完并 commit；在报告里把未能运行的 UI 命令逐条列出并标「未验证」，不要声称通过。用户随后会直接在真机上测试，所以每个单元还要在报告里写一条真机验证步骤（操作路径与期望现象）。
- 先红后绿：每单元报告写出红灯日志路径及失败断言名。

## 交付
1. 写 `docs/6-真机体验修复/R1-REPORT.md`（不超过 120 行）：逐单元的状态（完成、跳过及原因、未验证）、commit 哈希、改动文件、红绿日志路径与 `Executed N tests, with M failures` 原文行、与 Android 仍存在的差异。
1a. 在 R1-REPORT.md 末尾写「真机验收清单」：按单元列操作步骤与期望现象（F5 用恢复同一份 Android 备份后的缺源书验证）。注意手机上已装的是包标识 `com.starlitxiling.legado.ios` 的旧版，覆盖安装必须用该标识并配有效描述文件签名，否则会装出第二个空的「阅读」；不要改 `App/project.yml`，只在清单里写明安装前提。
2. 更新 `docs/6-真机体验修复/PROGRESS.md` 的任务表与下一步。
3. 最后一条消息：结论先行，未完成项与需用户决策项单独列出，不超过 600 字，不回贴代码与日志全文。
</task>
