<subagent_contract>
你是一个子代理。你的最后一条消息是唯一交付物，调用方看不到其他任何内容。必须遵守：
1. 所有发现、结论、文件路径都写进最后一条消息；禁止以计划、提问或"接下来我会…"收尾——先做完，再汇报。
2. 第一段先给结论（发生了什么/发现了什么），细节放后面。
3. 涉及代码的每条论断都带 `文件绝对路径:行号` 引用。
4. 如实汇报：测试失败就原样贴失败输出；跳过的步骤要说明；没验证过的事不得声称完成；不确定就标注"未验证"。
5. 只做指派的任务：不扩 scope、不顺手重构、不 commit/push（除非任务书明确要求）。
6. 改代码时贴合周边代码风格；注释只写代码本身无法表达的约束，不写解释本次改动的注释。
7. 用完整句子；禁止碎片化短语、箭头链（A→B）、自造缩写和代号、表情符号。
8. 被卡住就停下，精确说明缺什么信息；不许猜测、不许编造。
</subagent_contract>

<task>
目标：阶段 4 单元 B13b —— 设置项全集对齐：把 Android ThemeConfig / OtherConfig / BackupConfig 三个配置页面的全部设置项补进 iOS 设置页，key 名与 Android PreferKey / AppConfig 一致（以便 config.xml 备份互通），有 iOS 语义的全部实现，仅 Android 平台特有的记录为不支持。
工作目录：/Users/wujie/Work/legado-ios/.claude/worktrees/ios。工程：App/（XcodeGen 按目录收集，**不要运行 xcodegen、不改 project.yml / .xcodeproj**；新文件放 App/Sources/Features/<功能>/ 或 App/Sources/Shared/）；LegadoCore 在 Packages/LegadoCore（可新增目录与 public 入口，尽量不改既有文件；改动逐处列出）。已有能力：AnalyzeRule 引擎、AnalyzeUrlExecutor（含 webView 分支）、JsEngine/JavaHost、WebBook、Storage（Repository、AppDatabase.write、Migrations v1–v3、SourceStateRepository）、Entities、Network、Login/（SourceScriptBridge）、CheckSource/、LocalBook/（TXT / EPUB / MOBI / PDF）、Explore/、Images/、Backup/、WebView/、JsSource/、TTS/、Content/ContentProcessor、Reader/、Debug/、Export/、Cache/（CacheBook、BookExporter、BookHelp）；App 端 Features/{Bookshelf,Sources,ReplaceRules,Search,BookDetail,Toc,Reader,Settings,Backup,Explore,SourceLogin,CheckSource,LocalImport,Browser,ReadAloud,Download}、Shared/{Theme,EmptyStateView,KeychainStore,RemoteImage,HeadlessWebView}。ViewModel 与纯逻辑放不 import UIKit / SwiftUI 的文件，用 @Observable；单测走 tools/appcore-check（追加自己的目标，软链引用 App 下非 UI 文件）与 LegadoCore 测试。你不能跑 xcodebuild（主会话代跑）。并行任务会改其他目录与 RootTabView / AppContainer / JavaHost / Reader / Settings / BackupImporter 的不同区域：改共享文件前重新读取、只做最小局部插入、不重写。**验证一律在工作区内，不在 /tmp 做隔离副本**；swift test 用 CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/clang-cache" TMPDIR="$PWD/.build/tmp"（先 mkdir -p .build/tmp）--cache-path "$PWD/.build/cache" --disable-sandbox --disable-automatic-resolution --skip-update；磁盘只有约 3 GB，节省，不留大日志。Kotlin 只读，commit 2bdd3c58b，路径前缀 /Users/wujie/Work/legado-ios/app/src/main/java/io/legado/app/。Swift 语言模式 5；不加第三方依赖；不 commit；不联网。TDD 先红后绿；报告附命令与末尾 10 行、测试总数。汇报格式：中文 markdown ≤ 60 行。
Kotlin 规格：constant/PreferKey.kt（全部 key）、help/config/AppConfig.kt（默认值与派生属性）、ui/config/{ThemeConfigFragment,OtherConfigFragment,BackupConfigFragment}.kt（分组、入口、子页面）、help/storage/BackupConfig.kt（backupContent 12 项与 restoreIgnore 10 项）、help/config/ThemeConfig.kt（主题列表、日夜配色、保存 / 应用主题）、ui/welcome 与 ui/book/read/config 的封面配置项。已有：Features/Settings/{SettingsView,GeneralSettingsView}、Features/Backup/BackupPreferences（XML 偏好读写）、Shared/Theme。
缺口清单（复审盘点，逐项处理）：
- ThemeConfig：fontScale；配色 colorPrimary / colorAccent / colorBackground / colorBottomBackground / backgroundImage / backgroundImageBlurring 及七个 *Night 键；themeList（内置主题列表 + 保存日 / 夜主题 saveDayTheme / saveNightTheme）；welcomeStyle 子页（welcomeImagePath[Dark]、welcomeShowText[Dark]、welcomeShowIcon[Dark]）；coverConfig 子页 13 项（coverShowName / coverShowAuthor / coverShowNameN / coverShowAuthorN / coverHorizontal / coverTitleAdaptive / coverKeepPunctuation / coverFont / coverCustomFontSize / coverTitleLargeSize / coverTitleSmallSize / coverAuthorLargeSize / coverAuthorSmallSize）。**iOS 不适用、只记文档**：launcherIcon、barElevation、transparentStatusBar、immNavigationBar、transparentNavBar[Night]、wallpaperColorFollow / wallpaperColorAutoUpdate、disablePredictiveBack、bottomBarSkin。
- OtherConfig：auto_refresh、onlyUpdateRead、defaultToRead、showDiscovery、showDiscoveryFastScroller、showRss、defaultHomePage；userAgent、customHosts（接入现有 Network 的 UA / hosts 映射，若网络层无 hosts 支持则写明并只存偏好）、sourceEditMaxLine、antiAlias、bitmapCacheSize、imageRetainNum；replaceEnableDefault、readAloudByMediaButton、ignoreAudioFocus、autoClearExpired、showAddToShelfAlert、showMangaUi；jsSourceApiTokenRequired / jsSourceApiToken、recordLog、recordHttpLog；操作入口 checkSource（跳已有 CheckSource）、uploadRule（直链上传规则，接现有 Import）、shrinkDatabase（GRDB VACUUM）。**iOS 不适用、只记文档**：Cronet、webServiceWakeLock、defaultBookTreeUri、process_text、recordHeapDump、mediaButtonOnExit、autoUpdateVariant、liveUpdateNotifications、mcpPort、videoSetting。
- BackupConfig：webDavBookAutoRestore、syncBookProgressPlus、autoCheckNewBackup、backupUri（iOS 用文件夹书签 URL）；localPassword（备份 zip 加密——若现有 zip 写入器不支持加密则只存偏好并写明）、backupContent 12 项、restoreIgnore 10 项、lan_backup_transfer（记为不支持）。backupContent / restoreIgnore 必须真正接入 BackupExporter / BackupImporter 的文件选择与跳过逻辑。
产出：
1. App：Features/Settings 下按 Android 三页分组重排（ThemeSettingsView、OtherSettingsView、BackupSettingsView 及子页），偏好统一经一个 @Observable AppPreferences（key 名与 Android 一致，读写 UserDefaults，供 BackupPreferences 的 XML 导出 / 恢复直接使用）；Shared/Theme 接入配色与主题列表；书架封面接入 coverConfig；首页接入 defaultHomePage / showRss / showDiscovery。
2. LegadoCore：BackupExporter / BackupImporter 接入 backupContent / restoreIgnore；HttpClient 接入 userAgent 偏好（若已有入口则复用）。
3. docs/spec/settings-compat.md：三组全部 key 的对照表（已实现 / 只存偏好 / 不支持 + 理由），不贴数据。
4. 测试：AppPreferences 每个 key 的默认值与 Android 一致（抽全部 key 断言默认值）、XML 备份 round-trip 覆盖新 key、backupContent 关闭某项后 zip 不含对应文件、restoreIgnore 打开后导入跳过、coverConfig 影响封面文案的纯逻辑、主题保存 / 应用的纯逻辑。

</task>
