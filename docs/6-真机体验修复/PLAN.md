# 轮次 6 计划：真机体验修复与阅读器补齐

> 写于 2026-09-22。起点：`ios` 分支 `bb49f65bf`，用户已把 `dist/Legado-1.0-bbe2b6a5a.ipa` 装到 iPhone 并亲自体验，反馈四个问题。本轮以「用户第一小时的真实使用路径」为主线，先止血、再补阅读器、最后整体打磨。Kotlin 规格仍固定按 master `2bdd3c58b`，路径前缀 `/Users/xiling/Work/legado-ios/app/src/main/java/io/legado/app/`。

## 0. 用户反馈与根因（已由四个只读勘察 agent 定位，主会话逐条抽查核实）

| 用户现象 | 根因 | 证据 |
| --- | --- | --- |
| 进阅读界面弹「阅读样式加载失败：The data couldn't be read because it isn't in the correct format.」 | 用户 Android 备份的 `readConfig.json` 里 `underlineColor` 是字符串 `"#FF63C37D"`，Swift 模型是 `Int`，6 套样式全部 typeMismatch；`importThemes` 用 `try?` 吞掉数组解码错误后再按单对象解码，抛同一句话；自动加载失败直接阻塞式 alert，且每次进阅读都重弹 | `Packages/LegadoCore/Sources/LegadoCore/Reader/ReadBookConfig.swift:44,266-270`；`App/Sources/Features/Reader/ReaderStyleStore.swift:31-42`；`ReaderView.swift:202-204,217-219`；备份样本 `.build/fixtures-local/real-backup.zip` 内 `readConfig.json` |
| 主页弹「The operation couldn't be completed (Swift.CancellationError error 1.)」 | GRDB 在 Task 取消时让 `database.read/write` 抛 `CancellationError`；书架的 catch 直接把 `localizedDescription` 写进 `actionError`，没有取消过滤，且 `refreshBooks()` 成功后也不清空，所以一次取消就常驻 | `App/Sources/Features/Bookshelf/BookshelfView.swift:54,125,207,227,266`；`BookshelfViewModel.swift:87-89`；触发链 `BookshelfView.swift:134` 的 `.task(id:)` 与 `:206` 在 await 之后改 `selectedGroupID` 自取消 |
| 有些书「正文尚未缓存，且找不到对应书源」并卡住 | 两条叠加：(1) 本地书判定缺 Kotlin 的 `type == 0` 历史数据回退，从 Android 备份恢复的本地书被判成网络书去找 `loc_book` 书源；(2) load 失败后在前台 `await recoverSource`，遍历全部启用书源逐个跑四流程、无整体超时，期间 `isLoading = true` 使 `acceptsInput` 为 false，点不出菜单，返回又先等 `close()` 同步 WebDAV | `Packages/LegadoCore/Sources/LegadoCore/LocalBook/LocalBook.swift:8-10` 对照 Kotlin `help/book/BookExtensions.kt:50-56`；`App/Sources/Features/Reader/ReaderViewModel.swift:145,190,201,206,279-281,855-864`；`ReaderSourceRecovery.swift:12-53`；`ReaderChapterCache.swift:59-60,115`；`ReaderView.swift:161-169,271` |
| 界面选项缺文字/背景颜色选择，翻页动画不完整 | 颜色选择器其实存在但藏在「长按样式圆点」后的二级 Form 里，一级面板没有入口；内置背景图库（bgType=1）完全缺失；样式圆点预览遇到图片背景回落白色。翻页：五种都能切，四种有过渡动画，但零手势跟随（全仓无 `DragGesture`），覆盖模式转场固定从右侧进入不分方向，仿真模式未接 dataSource，滚动模式只装两屏 | `App/Sources/Features/Reader/ReaderInterfacePanel.swift:69-84,195-212`；`PageAnimation/CoverPageTransition.swift:6`；`SlidePageTransition.swift`；`SimulationPageTransition.swift:14-19`；`ScrollPageContainer.swift`；`ReaderInputView.swift:80-91` |

整体走查另发现三个影响面最大的系统性问题：核心包 42 个错误枚举中多数未实现 `LocalizedError`（含搜索主链路的 `WebBookError`），App 有 187 处把 `localizedDescription` 直接给用户看，所以英文系统文案会到处泄漏；工程只声明了 `en` 区域（`App/Legado.xcodeproj/project.pbxproj:1167-1171`，无 `.lproj`、无 `CFBundleLocalizations`），系统控件在中文手机上全英文；书架封面在主线程做 SHA256 加全尺寸解码（`App/Sources/Shared/RemoteImage.swift:33,80`、`CoverBitmapCache.swift:11`）。

## 1. 分阶段与开发单元

粒度：一个单元 = 一次 Codex 调用、一天内可完成、可独立验收、单独 commit。阶段内单元互不依赖可并行，阶段间按序。每个单元都要 TDD 先红后绿，报告附命令原文与末尾输出。

### 阶段 A：止血（用户第一小时必撞的阻断项）

**A1 阅读样式容错解码与静默回退**
- 范围：`Packages/LegadoCore/Sources/LegadoCore/Reader/ReadBookConfig.swift`、`App/Sources/Features/Reader/ReaderStyleStore.swift`、`ReaderView.swift:200-220`、对应测试。
- 改法：
  1. LegadoCore 内新增 internal 的宽松颜色解码：Int 颜色字段（`underlineColor`、`titleColor`、`titleNumberColor`、`tipColor`、`tipDividerColor`、`reviewIconColor`）在 `decodeIfPresent(Int)` 失败时接受 `String`，按 `#RRGGBB` / `#AARRGGBB` / 纯数字解析为 Android 风格有符号 Int（`"#FF63C37D"` 对应 `-10534531`），解析不了保留默认。不引入依赖，不复用 App 层 `ARGBColor`。
  2. `importThemes` 去掉 `try?`：先判顶层数组还是对象；数组逐元素解码，单元素失败记录索引并回退该位内置样式；全部失败才抛带字段名与索引的错误。
  3. `ReaderStyleStore.load()` 对 `readConfig.json` / `shareReadConfig.json` 解码失败不再抛出，回退 `bundledStyles()` 并把原始错误写入 App 日志（`AppLogStore`）。
  4. `ReaderView` 自动加载路径不再给 `styleError` 赋值，记日志后继续 `model.reflow`；alert 只保留给用户主动的导入 / 导出 / 删除操作。
- 验收：从 `.build/fixtures-local/real-backup.zip` 抽出 `readConfig.json` 精简为 fixture（保留 `"underlineColor": "#FF63C37D"`、三个多余键 `headerFontSize` / `footerFontSize` / `underlineOffset`、若干缺失键；来源是 `Legado_Max` 分叉，见第 4 节），断言 `importThemes` 返回 6 条且 `underlineColor == -10534531`；另加一条 `BookSource` 带未知键 `nextPageLazyLoad` 仍能解码的用例；`ReaderStyleStore` 塞入损坏 JSON 断言 `load()` 不抛且 `styles.count == 6`；现有导入导出往返用例保持通过。真机：恢复同一份备份后进阅读不弹窗，样式正常。

**A2 缺源与换源不再卡住阅读器**
- 范围：`Packages/LegadoCore/Sources/LegadoCore/LocalBook/LocalBook.swift`、`App/Sources/Features/Reader/ReaderViewModel.swift`、`ReaderSourceRecovery.swift`、`ReaderChapterCache.swift`、`ReaderView.swift:155-175,265-275`、对应测试。不动 `BookSourceRepository` 的主键匹配（与 Kotlin `BookSourceDao.kt:243` 一致）。
- 改法（对齐 Android `model/ReadBook.kt:1462-1481` 与 `ui/book/read/ReadBookViewModel.kt:192-195,342-383`）：
  1. `LocalBook.isLocal` 补 Kotlin 同款回退：`type == 0` 时只看 `origin == "loc_book"` 或前缀 `webDav::`。
  2. 无书源时不当异常处理：`ReaderChapterCache` 抛 `missingSource` 后由 `ReaderViewModel` 生成占位正文「加载正文失败\n没有书源」走正常排版，界面正常打开、可翻页、可开菜单。
  3. `recoverSource` 改为后台独立 Task，不再在 `load` / `openChapter` 内 `await`；用独立的 `recoveringMessage` 状态提示「正在自动换源…」，全程不置 `isLoading`，保证 `acceptsInput` 为真。换源成功后再切换正文。
  4. `ReaderSourceRecovery.find` 加整体超时（60 秒）与「无候选源」快速返回；候选源过滤去掉 `previous.isOnLineTxt` 这一多余守卫（Android 只查 `!isLocal && bookSource == null`）。
  5. `ReaderView` 的 ProgressView 与错误框改为互斥分支；错误框改可关闭提示条，带「换源 / 书源管理 / 返回」三个动作；返回按钮不等 `close()` 完成，进度同步放后台。
- 验收：`ReaderViewModel` 注入空书源库加无缓存章节，断言 `isLoading` 在 1 秒内复位、生成占位正文、`acceptsInput` 为真；`type == 0` 且 `origin == "loc_book"` 的书 `isLocal == true`；`ReaderSourceRecovery` 用假 client 断言超时后抛出而非挂起。真机：打开一本无源书立刻进入阅读界面，能点出菜单并返回。

**A3 取消错误过滤与书架错误状态治理**
- 范围：新增 `App/Sources/Shared/ErrorPresentation.swift`；`App/Sources/Features/Bookshelf/BookshelfView.swift:125,207,227,267`、`BookshelfViewModel.swift:87-89`；对应测试（`tools/appcore-check` 追加目标）。
- 改法：
  1. `extension Error { var isCancellation: Bool }`：`CancellationError`、`URLError.cancelled`、GRDB 桥出来的取消都算；`var presentableMessage: String?` 取消返回 nil。
  2. 书架四处 catch 与 ViewModel 取消时直接 return，不写 `actionError` / `errorMessage`；`refreshBooks()` 成功路径末尾清空 `actionError`。
  3. `BookshelfView.swift:206` 在 await 之后改 `selectedGroupID` 触发自取消的写法改为在 `.task` 之前决定分组，消除触发源。
- 验收：注入读取时抛 `CancellationError` 的 `BookshelfReading`，断言 `errorMessage == nil`；`isCancellation` 对三类错误的真值表。真机：反复切 tab、下拉刷新、进出详情，书架无红字。

**A4 错误文案中文化（用户决定：走稳妥路线，按功能分批、逐处改语义，不做一次性批量替换）**

拆成一个基础单元加三个功能批次，每批一次 Codex 调用、单独 commit、单独复审。目标不是把英文换成中文，而是让每条提示回答用户三个问题：出了什么事、和哪本书 / 哪个源 / 哪个文件有关、下一步能做什么。

- **A4a 基础设施与本地化声明**
  - 范围：`Packages/LegadoCore/Sources/LegadoCore/**` 所有 `enum *Error: Error`（42 个，重点 `WebBook.swift:3`、`WebDavClient.swift:3`、`ChapterRepository.swift:5`、`BackupArchive.swift:4`、`BackupAES.swift:59,71`、`RssParser.swift:116`、`HeadlessWebViewProtocol.swift:3`）；`App/Sources/Shared/ErrorPresentation.swift`（A3 产物上扩展）；`App/project.yml`、`App/Info.plist`；`App/Sources/Features/Settings/AppPreferences.swift:176-177` 两条英文硬编码。
  - 改法：
    1. 每个错误枚举实现 `LocalizedError`，`errorDescription` 说明发生了什么并带关联对象（书源名 / URL / 章节名 / 文件名），`recoverySuggestion` 给下一步（重试 / 换源 / 检查账号 / 去书源管理）。文案风格参照仓库里已经做得好的 `App/Sources/Features/Sources/ImportSupport.swift:22-33`。
    2. `presentableMessage` 兜底表：`URLError` 按 code 映射（无网络 / 超时 / 证书 / 主机不可达 / 取消返回 nil），`DecodingError` 统一「数据格式不正确」并附字段路径与来源文件名，GRDB 错误统一「本地数据库错误」并附操作名；未知错误保留原文但加中文前缀。再提供一个 `UserFacingError { title, message, actions }` 结构与统一的 `.errorBanner(_:)` 视图修饰符，供后续批次逐处替换裸字符串状态。
    3. `project.yml` 加 `zh-Hans` 到 knownRegions 并生成空 `zh-Hans.lproj`，`Info.plist` 加 `CFBundleLocalizations = [zh-Hans, en]`、`CFBundleDevelopmentRegion = zh-Hans`；改后 `xcodegen generate` 并把生成物一起提交。
    4. 新增守门测试：扫描 `App/Sources` 中把 `localizedDescription` 赋给非日志状态的行数，与一个「允许清单」文件对比，超出即失败；后续每批完成就从清单里删对应文件，清单归零即 A4 完成。
  - 验收：42 个枚举各有 `errorDescription` 单元测试且不含 "couldn't be completed" / "The data couldn't be read"；兜底表对 URLError 五种 code 的映射测试；守门测试的允许清单初始就是当前 187 处。真机：系统文件选择器与分享面板为中文。

- **A4b 阅读链路（58 处）**：`Features/Reader`（`ReaderViewModel.swift` 25 处、`ReaderTocView.swift`、`ReaderHighlightRulesView.swift`、`ReaderSearchView.swift` 等）加 `Toc`、`ReadAloud`、`Manga`、`AudioPlay`。逐处改成 `UserFacingError`，区分「正文加载失败（可换源 / 重试）」「目录刷新失败」「朗读引擎失败」「图片加载失败」四类，并把 A2 的缺源提示条接到同一套视图修饰符上。验收：断网打开未缓存章节、换源全失败、目录刷新失败三种场景真机提示中文且带动作按钮。
- **A4c 书源与发现搜索链路（32 处）**：`Features/Sources`、`Search`、`Explore`、`SourceLogin`、`CheckSource`、`ReplaceRules`。搜索失败展示逐源失败原因列表（与 C2 的搜索失败详情合并，此处一并做掉），书源导入 / 登录 / 校验错误带书源名与 URL。验收：0 书源搜索提示「请先导入书源」并可跳转；某源超时在列表里能看到该源名与「超时」。
- **A4d 数据与设置链路（97 处）**：`Features/Settings`（39 处）、`Bookshelf`（22 处）、`BookDetail`（19 处）、`LocalImport`（14 处）、`Backup`（10 处）、`Download`、`WebService`、`App`、`Shared`。WebDAV 错误区分账号密码错 / 路径不存在 / 网络；本地导入区分格式不支持 / 文件损坏 / 权限；备份恢复失败列出具体失败文件名。验收：错 WebDAV 密码、坏 JSON 导入、导入不支持格式三种场景真机提示中文且指向具体原因；守门测试允许清单归零。

- 批次顺序：A4a 先做（A4b 到 A4d 依赖它），之后 A4b 与 A4c 并行，A4d 最后。A4b 完成后即可打第一个阶段 A 真机包，不必等 A4c、A4d。

### 阶段 B：阅读器补齐（用户直接感知的功能差距）

**B1 翻页手势跟随（覆盖 / 滑动）与覆盖方向修正**
- 范围：`App/Sources/Features/Reader/PageAnimation/CoverPageTransition.swift`、`SlidePageTransition.swift`、`ReaderPagePresentation.swift`、`ReaderInputView.swift`，新增手势驱动层。Kotlin 参照 `ui/book/read/page/delegate/HorizontalPageDelegate.kt:47-90`、`CoverPageDelegate.kt`、`SlidePageDelegate.kt`。
- 改法：用 `DragGesture` 驱动相邻三页（上一页 / 当前页 / 下一页）的 offset，拖动实时跟手；松手按阈值（宽度 1/3 或速度）决定完成翻页或回弹；覆盖模式上一页从左侧压入、下一页从右侧盖上；翻到章首章尾沿用现有自动加载。
- 验收：UI 测试断言拖动半屏松手回弹、拖动过阈值翻页、回退方向正确；真机手感由用户验收。

**B2 界面面板重排、内置背景图与预览修复**
- 范围：`App/Sources/Features/Reader/ReaderInterfacePanel.swift`、`ReaderInfoView.swift:70-107`、`ReaderSettings.swift:159`、`ReaderStyleStore.swift`；从 `app/src/main/assets/bg/` 迁 24 张内置背景图到 SPM Resources。Kotlin 参照 `ui/book/read/config/ReadStyleDialog.kt`、`BgTextConfigDialog.kt`、`BgAdapter.kt:29-33`。
- 改法：
  1. 一级面板直接露出「文字颜色 / 背景颜色 / 背景图片」入口，不再只靠长按；长按仍进完整自定义页。
  2. 背景图片入口分「内置图库（网格 24 张，bgType=1）/ 相册与文件（bgType=2）」；`ReaderInfoView` 路径解析补 bgType=1 分支。
  3. 样式圆点预览按 bgType 渲染真实背景缩略图。
  4. 样式列表末尾加「+」新建；行距区间对齐 Android 的 -1.0 到 4.0；补「恢复预设布局」。
- 验收：选内置图后正文与圆点都显示该图，杀进程重开保持；导出样式再导入内置图引用不丢；单元测试覆盖 bgType 三种取值的解析。

**B3 仿真翻页交互化与滚动模式真连续**
- 范围：`SimulationPageTransition.swift`（改 `UIPageViewController` dataSource 加 `isDoubleSided`）、`ScrollPageContainer.swift`、`ReaderPagePresentation.swift:44-47`。Kotlin 参照 `SimulationPageDelegate.kt`、`ScrollPageDelegate.kt`。
- 验收：仿真模式手指可拖出卷曲角，松手完成或回弹；滚动模式整章连续滚动、有惯性、跨章无跳变；`pageAnimEInk` 字段被读取（`ThemePalette.swift:36` 去硬编码）。

**B4 样式细项补齐（可后置）**
- 正文 / 标题下划线配置与 CoreText 渲染（`underlineMode/Color/Width/Distance/BodyEnabled/TitleEnabled`）；提示区六槽位自定义模板编辑器（`ReaderInterfacePanel.swift:229-236` 不再把 template 置 nil）；暗色状态栏开关；网络导入样式；导出后系统分享；段评图标（SVG 模板 / 缩放 / 颜色）。按此顺序拆成 2 到 3 个单元。

### 阶段 C：整体打磨（从 Android 迁移用户的顺手程度）

**C1 书架性能与交互**
- 封面缓存 key 改用 URL 而非内容 SHA256，`CGImageSourceCreateThumbnailAtIndex` 降采样到格子尺寸，解码移出主线程；`RemoteImage.swift:80` 不再每次 body 把整个 `Book` 编成 JSON 当 task id。
- 书架长按改 `contextMenu`（置顶 / 移出 / 分组 / 详情），对齐 Android 长按菜单。
- 空书架给「导入书源 / 添加本地书」引导按钮；0 书源时搜索提示「请先导入书源」。
- 标签栏 `tabItem` 补文字 `Label`（`RootTabView.swift:28-47`）。
- 快速滚动条按索引分段，不生成几百个按钮（`BookshelfView.swift:88-92`）。

**C2 长任务反馈**
- 更新目录（`DownloadCenterModel.swift`）保存 Task 并暴露「停止」；进度默认可见（`AppPreferences.swift:17` 的 `showWaitUpCount`）。
- 搜索失败提供可展开的失败列表，不只写日志（`SearchView.swift:50,196`）。
- 阅读进度保存合并写入，不每翻一页同步写库（`ReaderViewModel.swift:340,403`）。

**C3 平台杂项**
- `Info.plist` 补 `NSLocalNetworkUsageDescription`（Web 服务用 `NWListener`）。
- 定时任务用 `onChange(of: scenePhase)` 驱动，修 `RootTabView.swift:66` 捕获旧快照的问题。
- 关键列表改语义字号或 `relativeTo:`，支持动态字体。
- 删除「MCP 服务 · 本轮暂不启用」开关（`SettingsView.swift:50`）。

## 2. 执行方式

- 通道：全部单元由 Codex（`gpt-6-astra`，`model_reasoning_effort=medium`）实现。用户已选稳妥路线，所以复审不再只挑核心单元：阶段 A 全部单元（A1、A2、A3、A4a 到 A4d）和 B1、B2 每个都派 `opus-explorer` 只读交叉复审，对照 Kotlin 逐条给 `Swift 文件:行号` 加 P 级；B3、B4 与阶段 C 用只读 Codex 新会话复审即可。复审 finding 用 `codex exec resume` 发回原实现会话返修，同一单元最多两轮。
- 每个改到用户可见文案或交互的单元，除单元测试外必须补至少一条 XCUITest 覆盖该场景（沿用 `.build/round5/final-ui.xcresult` 那套 UI 测试工程），由主会话或用户在本机跑。
- 每个单元的任务书按 `docs/tasks-archive/` 模板写（`<subagent_contract>` + 目标 / 工作目录 / Kotlin 规格 / iOS 入口 / 产出 / 测试要求），本文第 0 节与第 1 节的 `文件:行号` 直接抄进去。
- Codex 沙箱无网络、写不了 `~/Library`：`swift test`（LegadoCore、appcore-check）由 Codex 自己跑；`xcodegen generate` 与 `xcodebuild` 由本机主会话或用户跑。命令见 `docs/HANDOFF.md` 第 3 节。
- 合并顺序：第一批 A1 与 A3 并行；第二批 A2 与 A4a 并行（A4a 依赖 A3 的 `ErrorPresentation`）；第三批 A4b 与 A4c 并行；第四批 A4d。B 阶段 B1 与 B2 并行，B3 随后，B4 按细项拆分；C 阶段三单元并行。每个单元 commit 后更新 `PROGRESS.md`。
- 真机验收：每个阶段结束打一次 ipa 覆盖安装，由用户按第 3 节清单体验。

## 3. 阶段验收清单（用户真机）

阶段 A 结束：
1. 恢复 Android 备份后进任意一本书，不弹样式错误，样式与 Android 一致。
2. 书架反复切 tab、下拉刷新、进出详情，不出现英文错误。
3. 打开一本找不到书源的书，立刻进入阅读界面，看到「没有书源」占位与换源入口，能返回。
4. 断网搜索、错 WebDAV 密码、坏 JSON 导入，提示全部中文；系统文件选择器为中文。

阶段 B 结束：
5. 界面面板一级页能直接改文字色、背景色、选内置背景图；样式圆点显示真实背景。
6. 覆盖与滑动模式拖动跟手、松手回弹；仿真模式可拖卷角；滚动模式整章连续。

阶段 C 结束：
7. 几百本书的书架滚动流畅；长按有菜单；空书架有引导；标签栏有文字。
8. 更新目录可停止且有进度；搜索失败能看到哪些源失败。

## 4. 风险与未决

- **规格不前移，已核实。** 用户手机上装的不是我们跟的 `LegadoTeam/legado` 主线，而是分叉 `youfengknight/Legado_Max`（`underlineColor` 默认值 `"#FF63C37D"` 逐字命中，`underlineOffset` / `headerFontSize` / `footerFontSize` 三个多余键也全对上；版本落在 2026-05-23 到 08-28 之间的构建，最可能是 `beta-3.26.061723`）。主线自基线 `a6839374c` 起只有 2 个提交，未触碰任何实体 / 配置 / 备份文件。这是分叉间的 schema 分歧，主线 Android 拿这份备份同样会解码失败，前移到任何主线提交都解决不了。用真实备份对 Swift 模型 82 个字段逐键比对，类型冲突只有 `underlineColor` 一个，其余实体（Book / BookSource / BookChapter / ReplaceRule / RssSource）都只是多字段或少字段。A1 的宽松解码加「忽略未知键、缺失键回默认」就能覆盖 Max 分叉；A1 顺带把 `BookSource` 的 `nextPageLazyLoad` 之类未知键的忽略行为补进测试。
- 本机 `gh` 登录 token 已失效（`gh auth status` 报 invalid），只能匿名调公开 API；需要 `search/code` 或私有仓库时请用户重新 `gh auth login`。
- 「卡住」的具体形态未做运行时复现，A2 基于静态推断；若修后仍卡，下一步在真机抓 `AppLogStore` 日志定位。
- Android 备份恢复是否会把 `book.type` 写成 0 未追查（`App/Sources/Features/Backup/` 的 book 表映射），A2 的 `isLocal` 回退能兜住，但建议 A2 顺带核对。
- 上一轮全量 4198 个书源搜索通过率仅 356 条，与「找不到书源」是两回事（后者是书源库里根本没有该 origin），但意味着换源候选池实际可用的不多，A2 的超时必须有。
- 187 处错误文案调用点一次性批量替换有回归风险，A4 靠测试与 grep 归零把关，不做逐处语义改写。
