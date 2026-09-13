# 设置兼容性对照

规格为 Android cb664b84d 的 PreferKey、AppConfig、ThemeConfig、BackupConfig 和三个配置页及子页。仅记录能力，不记录用户数据。

状态区分「已实现」「只存偏好」「未实现」与「平台不适用」；功能尚未接入不等于 iOS 没有对应能力。customHosts 与 localPassword 保留原任务明确允许的偏好存储。launcherIcon 已接入系统调用入口、六套备用 PNG 和 iPhone / iPad 图标声明。完整 iOS 工程编译与真机效果仍由主会话验证。

AppPreferences 是唯一可观察偏好实现；BackupPreferences 为兼容名称。普通偏好保留 Android 键名与 XML 类型，读取时合并既有 XML 和当前 UserDefaults。缺省空路径对应 Android 未设置的可空字符串；设备名缺省由设备型号派生。主题列表不写入 config.xml，而是使用 themeConfig.json。

## 主题设置与子页

| Android key / 入口 | 状态 | iOS 行为或原因 |
| --- | --- | --- |
| `themeMode` | 已实现 | 保留 Android 键名；对应设置控件接入现有 iOS 页面或运行逻辑。 |
| `fontScale` | 已实现 | 0 跟随系统，8–16 对应 80%–160%；作用于应用默认文字，显式设置字体的控件仍保持自身样式。 |
| `colorPrimary` | 已实现 | 保留 Android 键名；对应设置控件接入现有 iOS 页面或运行逻辑。 |
| `colorAccent` | 已实现 | 保留 Android 键名；对应设置控件接入现有 iOS 页面或运行逻辑。 |
| `colorBackground` | 已实现 | 保留 Android 键名；对应设置控件接入现有 iOS 页面或运行逻辑。 |
| `colorBottomBackground` | 已实现 | 保留 Android 键名；对应设置控件接入现有 iOS 页面或运行逻辑。 |
| `backgroundImage` | 已实现 | 保留 Android 键名；对应设置控件接入现有 iOS 页面或运行逻辑。 |
| `backgroundImageBlurring` | 已实现 | 保留 Android 键名；对应设置控件接入现有 iOS 页面或运行逻辑。 |
| `colorPrimaryNight` | 已实现 | 保留 Android 键名；对应设置控件接入现有 iOS 页面或运行逻辑。 |
| `colorAccentNight` | 已实现 | 保留 Android 键名；对应设置控件接入现有 iOS 页面或运行逻辑。 |
| `colorBackgroundNight` | 已实现 | 保留 Android 键名；对应设置控件接入现有 iOS 页面或运行逻辑。 |
| `colorBottomBackgroundNight` | 已实现 | 保留 Android 键名；对应设置控件接入现有 iOS 页面或运行逻辑。 |
| `backgroundImageNight` | 已实现 | 保留 Android 键名；对应设置控件接入现有 iOS 页面或运行逻辑。 |
| `backgroundImageNightBlurring` | 已实现 | 严格使用 PreferKey 的 NightBlurring 次序，不创建 backgroundImageBlurringNight。 |
| `durThemeName` | 已实现 | 保留 Android 键名；对应设置控件接入现有 iOS 页面或运行逻辑。 |
| `durThemeNameNight` | 已实现 | 保留 Android 键名；对应设置控件接入现有 iOS 页面或运行逻辑。 |
| `themeList` | 已实现 | 操作入口，内置默认、典雅蓝、黑白、A屏黑四个主题；列表通过 themeConfig.json 备份。应用时只有目标明暗与当前实际明暗不同时才切换 themeMode，同明暗保留跟随系统或墨水屏模式。 |
| `saveDayTheme` | 已实现 | 操作入口；按名称保存或替换日间主题。 |
| `saveNightTheme` | 已实现 | 操作入口；按名称保存或替换夜间主题。 |
| `welcomeStyle` | 已实现 | 操作入口；应用内容出现后的欢迎覆盖页，不修改系统启动屏。 |
| `customWelcome` | 已实现 | 保留 Android 键名；对应设置控件接入现有 iOS 页面或运行逻辑。 |
| `welcomeShowTime` | 已实现 | 保留 Android 键名；对应设置控件接入现有 iOS 页面或运行逻辑。 |
| `welcomeImagePath` | 已实现 | 保留 Android 键名；对应设置控件接入现有 iOS 页面或运行逻辑。 |
| `welcomeImagePathDark` | 已实现 | 保留 Android 键名；对应设置控件接入现有 iOS 页面或运行逻辑。 |
| `welcomeShowText` | 已实现 | 保留 Android 键名；对应设置控件接入现有 iOS 页面或运行逻辑。 |
| `welcomeShowTextDark` | 已实现 | 保留 Android 键名；对应设置控件接入现有 iOS 页面或运行逻辑。 |
| `welcomeShowIcon` | 已实现 | 保留 Android 键名；对应设置控件接入现有 iOS 页面或运行逻辑。 |
| `welcomeShowIconDark` | 已实现 | 保留 Android 键名；对应设置控件接入现有 iOS 页面或运行逻辑。 |
| `coverConfig` | 已实现 | 操作入口；13 个文案和字体选项作用于默认封面。 |
| `coverShowName` | 已实现 | 保留 Android 键名；对应设置控件接入现有 iOS 页面或运行逻辑。 |
| `coverShowAuthor` | 已实现 | 保留 Android 键名；对应设置控件接入现有 iOS 页面或运行逻辑。 |
| `coverShowNameN` | 已实现 | 保留 Android 键名；对应设置控件接入现有 iOS 页面或运行逻辑。 |
| `coverShowAuthorN` | 已实现 | 保留 Android 键名；对应设置控件接入现有 iOS 页面或运行逻辑。 |
| `coverHorizontal` | 已实现 | 保留 Android 键名；对应设置控件接入现有 iOS 页面或运行逻辑。 |
| `coverTitleAdaptive` | 已实现 | 保留 Android 键名；对应设置控件接入现有 iOS 页面或运行逻辑。 |
| `coverKeepPunctuation` | 已实现 | 保留 Android 键名；对应设置控件接入现有 iOS 页面或运行逻辑。 |
| `coverFont` | 已实现 | 区分本机字体路径、file URL 与 PostScript 名；仅文件打包为 coverFont.ttf 并在恢复时重绑，字体名原样保留。缺失键按 Android 清除，忽略封面配置时保持原值。 |
| `coverCustomFontSize` | 已实现 | 保留 Android 键名；对应设置控件接入现有 iOS 页面或运行逻辑。 |
| `coverTitleLargeSize` | 已实现 | 保留 Android 键名；对应设置控件接入现有 iOS 页面或运行逻辑。 |
| `coverTitleSmallSize` | 已实现 | 保留 Android 键名；对应设置控件接入现有 iOS 页面或运行逻辑。 |
| `coverAuthorLargeSize` | 已实现 | 保留 Android 键名；对应设置控件接入现有 iOS 页面或运行逻辑。 |
| `coverAuthorSmallSize` | 已实现 | 保留 Android 键名；对应设置控件接入现有 iOS 页面或运行逻辑。 |
| `useDefaultCover` | 已实现 | 保留 Android 键名；对应设置控件接入现有 iOS 页面或运行逻辑。 |
| `defaultCover` | 已实现 | 保留 Android 键名；对应设置控件接入现有 iOS 页面或运行逻辑。 |
| `defaultCoverDark` | 已实现 | 保留 Android 键名；对应设置控件接入现有 iOS 页面或运行逻辑。 |
| `loadCoverOnlyWifi` | 已实现 | NWPathMonitor 跟踪 Wi-Fi；非 Wi-Fi 时阻止封面网络请求，磁盘缓存、data URL 和本地图片仍可用，网络变化自动重试。 |
| `coverRule` | 已实现 | 提供 JSON 编辑保存与内置 Android 规则；缺失封面时使用既有规则引擎搜索，支持规则中的编码和 JSONPath 调用。 |
| `readRecordCover` | 已实现 | 阅读记录页面使用日间缺省封面，支持导入文件；文件归 covers 其他封面，恢复时重绑路径。 |
| `readRecordCoverDark` | 已实现 | 阅读记录页面使用夜间缺省封面，支持导入文件；文件归 covers 其他封面，恢复时重绑路径。 |
| `launcherIcon` | 已实现 | Android 使用 ic_launcher、launcher1…6 切换 Activity alias（help/LauncherIconHelp.kt:17–62；res/values/array_values.xml:4–11）。iOS 调用 UIApplication.setAlternateIconName，仅列出 Bundle 已声明图标，成功后写同名偏好。tools/icon-render 从 Android cb664b84d 的六套自适应图标生成 120×120、180×180 不透明 PNG；project.yml 在 CFBundleIcons 与 CFBundleIcons~ipad 下登记 launcher1…6，CFBundleIconFiles 引用同名资源。按任务约定将 108dp 图层合成后裁取中心 72dp，主图标保持不变。工程生成、打包与实际切换由主会话验证。 |
| `barElevation` | 未实现 | Android 为工具栏阴影高度（lib/theme/MaterialValueHelper.kt:145–155）。iOS 可用栏外观或自绘阴影实现视觉等价；当前尚未接入，不能归为平台无能力。 |
| `transparentStatusBar` | 未实现 | Android 控制状态栏透明背景（base/BaseActivity.kt:252–254）。iOS 可控制状态栏后方的背景和安全区延伸；当前未将该键映射到此行为，并非平台无能力。 |
| `immNavigationBar` | 平台不适用 | Android 切换系统底部导航栏原色或加深色（base/BaseActivity.kt:263–269）。iOS 没有 Android 三键系统导航栏，Home indicator 也没有可设置背景色的等价公开属性。 |
| `transparentNavBar` | 平台不适用 | Android 指系统底部导航栏透明度，不是应用的 NavigationStack（help/config/ThemeConfig.kt:286–295）。iOS 无同类 Android 系统导航栏，不能原样映射该键。 |
| `transparentNavBarNight` | 平台不适用 | 与 transparentNavBar 相同，是 Android 系统底部导航栏的夜间分支（help/config/ThemeConfig.kt:286）。iOS 的应用导航栏透明效果是不同对象。 |
| `wallpaperColorFollow` | 平台不适用 | Android 读取 WallpaperManager.getWallpaperColors(FLAG_SYSTEM)（lib/theme/WallpaperTheme.kt:132–133）。iOS 公共 SDK 不提供读取用户系统壁纸或其颜色的接口，不能实现该自动取色来源。 |
| `wallpaperColorAutoUpdate` | 平台不适用 | Android 监听 WallpaperManager.OnColorsChangedListener（lib/theme/WallpaperTheme.kt:211–223）。iOS 公共 SDK 没有系统壁纸颜色变化监听接口。 |
| `disablePredictiveBack` | 平台不适用 | Android 13 OnBackInvokedDispatcher 回调用于禁用系统预测性返回动画（base/BaseActivity.kt:108–120）。iOS 的交互返回手势属于另一套导航机制，没有此 Android 动画开关。 |
| `bottomBarSkin` | 未实现 | Android 导入并应用底栏图标皮肤（help/BottomBarSkinManager.kt:34–55；ui/config/ThemeConfigFragment.kt:258）。iOS 可以替换 TabView 图标，皮肤导入与格式映射当前未实现，不能归为平台无能力。 |

## 其他设置

| Android key / 入口 | 状态 | iOS 行为或原因 |
| --- | --- | --- |
| `language` | 已实现 | 保留 Android 键名；对应设置控件接入现有 iOS 页面或运行逻辑。 |
| `auto_refresh` | 已实现 | 保留 Android 键名；对应设置控件接入现有 iOS 页面或运行逻辑。 |
| `onlyUpdateRead` | 已实现 | 仅更新没有未读章节的书，按 totalChapterNum - durChapterIndex - 1 判断。 |
| `defaultToRead` | 已实现 | 保留 Android 键名；对应设置控件接入现有 iOS 页面或运行逻辑。 |
| `showDiscovery` | 已实现 | 保留 Android 键名；对应设置控件接入现有 iOS 页面或运行逻辑。 |
| `showDiscoveryFastScroller` | 已实现 | 保留 Android 键名；对应设置控件接入现有 iOS 页面或运行逻辑。 |
| `showRss` | 已实现 | 保留 Android 键名；对应设置控件接入现有 iOS 页面或运行逻辑。 |
| `defaultHomePage` | 已实现 | bookshelf/explore/rss/my；被隐藏的首页回落书架。 |
| `userAgent` | 已实现 | 默认 UA 只在最终客户端阶段补入；用户偏好覆盖固定默认值，书源显式 UA 优先，显式字符串 null 删除 UA 且后续客户端不再补回。空偏好沿用网络组件默认 UA。 |
| `customHosts` | 只存偏好 | 当前 HttpClient 没有自定义 DNS/Hosts 执行入口；按任务约定仅保存 JSON。 |
| `sourceEditMaxLine` | 已实现 | 控制表单字段可见行数，JSON 编辑器保持固定滚动区域。 |
| `antiAlias` | 已实现 | 控制阅读文本抗锯齿及图片插值。 |
| `bitmapCacheSize` | 已实现 | 按解码图像成本限制 NSCache；0 禁用共享位图缓存。 |
| `imageRetainNum` | 已实现 | 漫画保存进度时按章节裁剪磁盘图片缓存，保留当前章节向前指定数量、向后 preDownloadNum 的闭区间；0 不清理，其他书与封面缓存不受影响。升级前未建立章节索引的图片保守保留，访问对应章节后纳入清理。 |
| `preDownloadNum` | 已实现 | 保留 Android 键名；对应设置控件接入现有 iOS 页面或运行逻辑。 |
| `threadCount` | 已实现 | 保留 Android 键名；对应设置控件接入现有 iOS 页面或运行逻辑。 |
| `bookshelfSort` | 已实现 | 保留 Android 键名；对应设置控件接入现有 iOS 页面或运行逻辑。 |
| `replaceEnableDefault` | 已实现 | 保留 Android 键名；对应设置控件接入现有 iOS 页面或运行逻辑。 |
| `readAloudByMediaButton` | 已实现 | 控制停止状态下媒体播放键是否启动朗读；暂停后的继续播放不受影响。 |
| `ignoreAudioFocus` | 已实现 | 下次启动音频时使用 mixWithOthers。 |
| `autoClearExpired` | 已实现 | 前台激活时清理 caches 表中已到期且 deadline 非零的记录。 |
| `showAddToShelfAlert` | 已实现 | 保留 Android 键名；对应设置控件接入现有 iOS 页面或运行逻辑。 |
| `showMangaUi` | 已实现 | 保留 Android 键名；对应设置控件接入现有 iOS 页面或运行逻辑。 |
| `jsSourceApiTokenRequired` | 已实现 | 保留 Android 键名；对应设置控件接入现有 iOS 页面或运行逻辑。 |
| `jsSourceApiToken` | 已实现 | 保留原键，网络服务读取当前令牌；按 Android 规则不导出或恢复令牌。 |
| `recordLog` | 已实现 | 将书源调试输出写入系统日志。 |
| `recordHttpLog` | 已实现 | 记录请求方法、响应状态和主机；不记录正文、凭据及 Cookie。 |
| `checkSource` | 已实现 | 读取全部书源并进入已有 CheckSourceView。 |
| `uploadRule` | 已实现 | 复用 ManagementImport 从 URL/文件读取 JSON；验证并保存 directLinkUploadRule.json，参与规则备份。 |
| `cleanCache` | 已实现 | 保留 Android 键名；对应设置控件接入现有 iOS 页面或运行逻辑。 |
| `clearWebViewData` | 已实现 | 保留 Android 键名；对应设置控件接入现有 iOS 页面或运行逻辑。 |
| `shrinkDatabase` | 已实现 | 调用 GRDB writer.vacuum()，不包裹在事务内。 |
| `webPort` | 已实现 | 使用已有 Web 服务设置入口。 |
| `Cronet` | 未实现 | Android 接入 CronetLoader 和 OkHttp CronetInterceptor（help/http/Cronet.kt:8–19）。当前 iOS 使用 URLSession，未集成 iOS Cronet；这是网络引擎依赖缺口，不代表 iOS 无法提供该类引擎。 |
| `webServiceWakeLock` | 平台不适用 | Android 为 WebService 获取 PARTIAL_WAKE_LOCK（service/WebService.kt:76–80）。iOS 没有让普通 HTTP 服务无限后台保持 CPU 唤醒的等价权限；有限后台任务不能承诺同样语义。 |
| `defaultBookTreeUri` | 未实现 | Android 通过系统目录选择器保存 SAF tree URI（ui/config/OtherConfigFragment.kt:69、142）。Android URI 本身不能在 iOS 解析，但同用途的安全作用域目录书签可实现；本地书默认目录选择尚未接入此键。 |
| `process_text` | 未实现 | Android ACTION_PROCESS_TEXT 接收外部选中文本（receiver/SharedReceiverActivity.kt:32；ui/book/read/TextActionMenu.kt:236）。iOS 没有 Android Intent/Activity 注册机制；类似跨应用文本导入需要独立 Share/Action Extension，当前未实现该扩展。 |
| `recordHeapDump` | 平台不适用 | Android 在 OutOfMemoryError 后触发托管堆转储（help/CrashHandler.kt:81–82）。iOS App 无 ART/Java 托管堆与 HPROF 转储接口；Xcode 内存诊断不等于运行时 Android 堆文件导出。 |
| `mediaButtonOnExit` | 未实现 | Android 在没有 Activity 时允许 MediaButtonReceiver 恢复朗读（receiver/MediaButtonReceiver.kt:111–120）；这不等同于用户强制停止应用。iOS 可在保留媒体会话时根据该键控制 Remote Command 是否恢复播放，当前未接线，不能以强制退出限制否定此功能。 |
| `autoUpdateVariant` | 未实现 | Android 每隔 24 小时检查 GitHub variant 发行版并显示更新对话框（ui/main/MainActivity.kt:297–310）。iOS 可以检查其发行渠道版本并提供跳转；当前没有该渠道的映射和更新检查，不能直接消费 Android APK，也不能归为版本检查能力缺失。 |
| `liveUpdateNotifications` | 未实现 | Android 使用 promoted progress notifications（utils/NotificationExtensions.kt:31–59）。iOS 可用 ActivityKit Live Activities 提供进度展示，但需要 Widget Extension 和声明；当前未接入，不能归为平台无能力。 |
| `mcpPort` | 未实现 | Android 设置 MCP 服务监听端口，默认 1236（service/McpService.kt:226）。iOS 前台可建立监听服务；当前缺少 MCP 服务实现，此项不是平台端口能力缺失。 |
| `videoSetting` | 未实现 | Android 打开自有视频设置对话框（ui/config/OtherConfigFragment.kt:141，ui/video/config/SettingsDialog.kt:25–48）。播放器选项可以依据 AVPlayer 能力映射，当前没有对等设置页，不能笼统归为 Android 特有。 |

## 备份设置

| Android key / 入口 | 状态 | iOS 行为或原因 |
| --- | --- | --- |
| `web_dav_url` | 已实现 | 沿用现有 WebDAV 账号页面与 Keychain，不把凭据写入 config.xml。 |
| `web_dav_account` | 已实现 | 沿用现有 WebDAV 账号页面与 Keychain。 |
| `web_dav_password` | 已实现 | 沿用现有 WebDAV 账号页面与 Keychain。 |
| `webDavDir` | 已实现 | 保留 Android 键名；对应设置控件接入现有 iOS 页面或运行逻辑。 |
| `webDavDeviceName` | 已实现 | 保留 Android 键名；对应设置控件接入现有 iOS 页面或运行逻辑。 |
| `webDavBookAutoRestore` | 已实现 | 打开本地书且文件缺失时，从 WebDAV books 目录精确匹配文件名并下载，独立绑定本机路径，保留 bookUrl 关联身份；显式 webDav:: 来源遵守 Android 的优先规则。 |
| `syncBookProgress` | 已实现 | 启动时一次列出远端进度，仅恢复远端修改时间晚于 syncTime 且阅读位置领先的记录；同时作为阅读页同步总开关。 |
| `syncBookProgressPlus` | 已实现 | 阅读页网络恢复时同步并提示领先进度；退出阅读时开启则先同步，关闭则仅上传。阅读同步按位置比较，不套用启动恢复的 syncTime 门槛。 |
| `autoCheckNewBackup` | 已实现 | 前台比较远端修改时间与本机备份/恢复时间，显示可关闭提示。 |
| `backupUri` | 已实现 | 文件夹 URL 作为偏好；安全作用域书签单独本机保存，导出时解析书签。Android 规则禁止跨设备恢复该键。 |
| `localPassword` | 只存偏好 | 当前 ZIP 写入器没有加密能力；按任务约定仅保存，生成的 ZIP 不加密。 |
| `autoBackup` | 已实现 | 保留 Android 键名；对应设置控件接入现有 iOS 页面或运行逻辑。 |
| `autoBackupWebDav` | 已实现 | 保留 Android 键名；对应设置控件接入现有 iOS 页面或运行逻辑。 |
| `autoBackupIntervalDays` | 已实现 | 保留 Android 键名；对应设置控件接入现有 iOS 页面或运行逻辑。 |
| `onlyLatestBackup` | 已实现 | 保留 Android 键名；对应设置控件接入现有 iOS 页面或运行逻辑。 |
| `web_dav_backup` | 已实现 | 保留 Android 键名；对应设置控件接入现有 iOS 页面或运行逻辑。 |
| `web_dav_restore` | 已实现 | 保留 Android 键名；对应设置控件接入现有 iOS 页面或运行逻辑。 |
| `backupContent` | 已实现 | 操作入口；选择值保存为与 Android restoreIgnore.json 相同的排除布尔映射，不伪造 config.xml 键。 |
| `restoreIgnore` | 已实现 | 操作入口；10 项均接入文件跳过、偏好过滤或本地书行过滤。 |
| `lan_backup_transfer` | 未实现 | Android 提供局域网备份传输入口（ui/config/BackupConfigFragment.kt:278、350）。iOS 可在获准访问本地网络后实现同类传输；当前未实现协议与界面，属于功能缺口而非平台无能力。 |

## 备份内容的 12 项

该映射中的 true 表示排除。backupReadRecordCovers、backupCookies、backupSourceVariables 缺省不选，显式 false 才包含；其余项缺省包含。

| key | 状态 | 文件选择 |
| --- | --- | --- |
| `backupBookshelf` | 已实现 | bookshelf.json、bookGroup.json、bookMemo.json |
| `backupAnnotations` | 已实现 | bookmark.json、highlight.json、highlightRule.json |
| `backupSources` | 已实现 | bookSource.json、rssSources.json、rssStar.json、sourceSub.json |
| `backupRules` | 已实现 | replaceRule.json、txtTocRule.json、httpTTS.json、keyboardAssists.json、dictRule.json、autoTask.json、servers.json、directLinkUploadRule.json、coverRule.json |
| `backupHistory` | 已实现 | readRecord.json、searchHistory.json |
| `backupReadRecordCovers` | 已实现 | 打包 readRecord.json 引用的 readRecordCovers 文件，依赖 backupHistory；关闭时清空对应记录路径，恢复时重绑本机目录。 |
| `backupSettings` | 已实现 | readConfig.json、shareReadConfig.json、themeConfig.json、config.xml、videoConfig.xml |
| `backupPersistedCovers` | 已实现 | 打包 covers 下 32 位十六进制名称的 .cover 文件；关闭时清空 persistedCoverUrl，恢复时重绑。 |
| `backupOtherCovers` | 已实现 | 打包 covers 中其余文件，包含默认封面与阅读记录占位图；恢复至本机资源目录。 |
| `backupBackgrounds` | 已实现 | 从实际完整阅读配置列表（含导入样式和 bgType）收集 bg 文件，并兼容 iOS 日夜主题背景引用；恢复重绑路径，ignoreReadConfig 开启时跳过背景文件。 |
| `backupCookies` | 已实现 | cookies.json |
| `backupSourceVariables` | 已实现 | runtimeSourceCache.json |

## 恢复忽略的 10 项

缺省均不忽略。本机选择不会被待恢复归档改写；选择 JSON 独立保存，不并入 config.xml。导出也按 keyIsNotIgnore 过滤偏好及阅读、主题配置文件；忽略封面配置时不打包封面字体。恢复缺失键时清除 coverFont 与阅读记录封面，重置自适应标题、自定义字号等默认值；忽略组保留原值。

| key | 状态 | 忽略范围 |
| --- | --- | --- |
| `readConfig` | 已实现 | 阅读偏好组与 readConfig.json / shareReadConfig.json |
| `themeMode` | 已实现 | themeMode 偏好 |
| `themeConfig` | 已实现 | 日夜 14 个配色偏好与 themeConfig.json |
| `coverConfig` | 已实现 | Android coverPrefKeys 偏好组，并保护 iOS 固定命名的日夜默认封面不被覆盖。 |
| `bookshelfLayout` | 已实现 | bookshelfLayout 偏好 |
| `showRss` | 已实现 | showRss 偏好 |
| `threadCount` | 已实现 | threadCount 偏好 |
| `localBook` | 已实现 | 本地书及 webDav:: 来源书架行 |
| `ignoreCookies` | 已实现 | cookies.json |
| `ignoreSourceVariables` | 已实现 | runtimeSourceCache.json |

## 验证与限制

执行 `bash tools/appcore-check/check-b13b.sh` 与 LegadoCore 全量测试，全部缓存与临时目录位于工作区。测试覆盖完整默认值字典、XML 类型往返、主题保存应用、封面布局与内置规则、章节图片保留、三项 WebDAV 偏好行为、实际资源归档排除、恢复忽略及路径重绑。WebDAV 和封面搜索均使用假客户端。

资源使用 Application Support/LegadoResources 下的 covers、readRecordCovers、bg 目录。Android 忽略 defaultCover/defaultCoverDark 的 XML 偏好，iOS 使用固定文件名保存这两张图片并在恢复后作为缺省路径；任意 Android 封面文件仍保留，但无法凭文件内容推断其日夜用途。文件型字体以 coverFont.ttf 打包，PostScript 字体名不产生字体资源。主题背景引用作为兼容扩展参加背景资源收集。

未运行 xcodegen、xcodebuild，未修改工程文件，未提交。PreferenceControls 及部分新增 UI 已用 iOS SDK、保留 MainActor 隔离的依赖桩完成 Swift 5 类型检查；这不替代完整工程构建。
