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
目标：阶段 4 单元 B16 —— 备用启动图标素材：把 Android 的 6 套自适应图标（res/mipmap-anydpi-v26/launcherN.xml → background 色值 / drawable + foreground VectorDrawable res/drawable/ic_launcherN.xml）栅格化为 iOS 备用图标 PNG，并接入 project.yml，使 B13b 已实现的 LauncherIconSettingsView（UIApplication.setAlternateIconName）可用。
工作目录：/Users/wujie/Work/legado-ios/.claude/worktrees/ios。工程：App/（XcodeGen 按目录收集，**不要运行 xcodegen、不改 project.yml / .xcodeproj**；新文件放 App/Sources/Features/<功能>/ 或 App/Sources/Shared/）；LegadoCore 在 Packages/LegadoCore（可新增目录与 public 入口，尽量不改既有文件；改动逐处列出）。已有能力：AnalyzeRule 引擎、AnalyzeUrlExecutor（含 webView 分支）、JsEngine/JavaHost、WebBook、Storage（Repository、AppDatabase.write、Migrations v1–v3、SourceStateRepository）、Entities、Network、Login/（SourceScriptBridge）、CheckSource/、LocalBook/（TXT / EPUB / MOBI / PDF）、Explore/、Images/、Backup/、WebView/、JsSource/、TTS/、Content/ContentProcessor、Reader/、Debug/、Export/、Cache/（CacheBook、BookExporter、BookHelp）；App 端 Features/{Bookshelf,Sources,ReplaceRules,Search,BookDetail,Toc,Reader,Settings,Backup,Explore,SourceLogin,CheckSource,LocalImport,Browser,ReadAloud,Download}、Shared/{Theme,EmptyStateView,KeychainStore,RemoteImage,HeadlessWebView}。ViewModel 与纯逻辑放不 import UIKit / SwiftUI 的文件，用 @Observable；单测走 tools/appcore-check（追加自己的目标，软链引用 App 下非 UI 文件）与 LegadoCore 测试。你不能跑 xcodebuild（主会话代跑）。并行任务会改其他目录与 RootTabView / AppContainer / JavaHost / Reader / Settings / BackupImporter 的不同区域：改共享文件前重新读取、只做最小局部插入、不重写。**验证一律在工作区内，不在 /tmp 做隔离副本**；swift test 用 CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/clang-cache" TMPDIR="$PWD/.build/tmp"（先 mkdir -p .build/tmp）--cache-path "$PWD/.build/cache" --disable-sandbox --disable-automatic-resolution --skip-update；磁盘只有约 2 GB，节省，不留大日志。Kotlin 只读，commit 2bdd3c58b，路径前缀 /Users/wujie/Work/legado-ios/app/src/main/java/io/legado/app/。Swift 语言模式 5；不加第三方依赖；不 commit；不联网。TDD 先红后绿；报告附命令与末尾 10 行、测试总数。汇报格式：中文 markdown ≤ 60 行。
方法：写一个 Swift 命令行脚本 tools/icon-render/（SwiftPM 可执行，macOS 运行，CoreGraphics）：解析 VectorDrawable XML（viewportWidth / viewportHeight、<path pathData fillColor strokeColor strokeWidth fillAlpha>、<group> 的 translate / scale / rotation / pivot、<clip-path>），pathData 按 SVG path 语法（M L H V C S Q T A Z 及小写相对形式、隐式重复）转成 CGPath；背景：color 资源取 res/values/*.xml 色值，drawable 则递归渲染；按自适应图标规范以 108dp 画布、把前景 / 背景合成后取中心 72dp 安全区裁成正方形，输出 App/Resources/AlternateIcons/launcherN@2x.png（120×120）与 @3x.png（180×180），无透明通道（iOS 图标要求不透明）。主图标不动。settings-compat.md 的 launcherIcon 行改为「已实现」。
产出：1. tools/icon-render 脚本与生成的 12 张 PNG；2. project.yml 加 CFBundleIcons / CFBundleIcons~ipad 的 CFBundleAlternateIcons（launcher1…launcher6 各 CFBundleIconFiles）与资源目录（按现有 sources / resources 写法追加，不改其他键；**允许改 project.yml，仍不运行 xcodegen**）；3. 测试：tools/icon-render 自带 XCTest：pathData 解析（含弧线与相对命令）、简单 VD 渲染到已知像素、6 套图标生成尺寸与非透明断言；渲染结果的 6 张 @2x 缩略描述（文字）。

</task>
