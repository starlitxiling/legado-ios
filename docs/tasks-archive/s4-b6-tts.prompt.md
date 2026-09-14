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
目标：阶段 4 单元 B6 —— 听书：系统 TTS（AVSpeechSynthesizer）与在线 HttpTTS 源（合成音频后 AVAudioPlayer / AVPlayer 播放）、后台音频、锁屏 / 控制中心控制、定时停止、朗读进度与阅读器联动（按段朗读、高亮当前段、自动翻页与切章）。
工作目录：/Users/wujie/Work/legado-ios/.claude/worktrees/ios。工程：App/（XcodeGen 按目录收集，**不要运行 xcodegen、不改 project.yml / .xcodeproj**；新文件放 App/Sources/Features/<功能>/ 或 App/Sources/Shared/）；LegadoCore 在 Packages/LegadoCore（可新增目录与 public 入口，尽量不改既有文件；改动逐处列出）。已有能力：AnalyzeRule 引擎、AnalyzeUrlExecutor（webView 分支目前抛未实现）、JsEngine/JavaHost（webView* 方法为桩）、WebBook、Storage（Repository、AppDatabase.write、SourceStateRepository）、Entities、Network、Login/、CheckSource/、LocalBook/（TXT / EPUB、ZipReader）、Explore/、Images/、Backup/；App 端 Features/{Bookshelf,Sources,ReplaceRules,Search,BookDetail,Toc,Reader,Settings,Backup,Explore,SourceLogin,CheckSource,LocalImport}、Shared/{Theme,EmptyStateView,KeychainStore,RemoteImage}。ViewModel 与纯逻辑放不 import UIKit / SwiftUI 的文件，用 @Observable；单测走 tools/appcore-check（追加自己的目标，软链引用 App 下非 UI 文件）与 LegadoCore 测试。你不能跑 xcodebuild（主会话代跑）。并行任务会改其他目录与 RootTabView / AppContainer / JavaHost 的不同区域：改共享文件前重新读取、只做最小局部插入、不重写。**验证一律在工作区内，不在 /tmp 做隔离副本**；swift test 用 CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/clang-cache" TMPDIR="$PWD/.build/tmp"（目录已存在）--cache-path "$PWD/.build/cache" --disable-sandbox --disable-automatic-resolution --skip-update；磁盘只有约 3 GB，节省。Kotlin 只读，commit cb664b84d，路径前缀 /Users/wujie/Work/legado-ios/app/src/main/java/io/legado/app/。Swift 语言模式 5；不加第三方依赖；不 commit；不联网。TDD 先红后绿；报告附命令与末尾 10 行、测试总数。汇报格式：中文 markdown ≤ 60 行。
Kotlin 规格：service/BaseReadAloudService.kt（状态机：播放 / 暂停 / 停止、按段索引朗读、上下段、定时、与 ReadBook 的进度同步、耳机 / 媒体按键）、service/TTSReadAloudService.kt（系统 TTS：语速、utterance 队列、onDone 推进）、service/HttpReadAloudService.kt（916 行：HttpTTS 源的 url 规则（含 {{speakText}} / {{speakSpeed}} 内插）、合成文件缓存、并发预合成、播放队列、错误重试）、data/entities/HttpTTS.kt（id / name / url / contentType / concurrentRate / loginUrl 等）、help/config/ReadAloud 相关配置（语速、音量、定时）、ui/book/read/ReadAloudDialog。
产出：
1. LegadoCore：TTS/{ReadAloudEngine.swift（状态机与段队列，不依赖 AVFoundation，可注入 Speaker protocol）,HttpTTSSource.swift（规则求值走 AnalyzeUrlExecutor，合成音频下载与缓存，Entities 补 HttpTTS 与 Storage 表 / 迁移 v3）}；备份导入的 httpTTS.json 接入 BackupImporter（回源 Restore.kt 顺序，改动逐处列出）。
2. App：Features/ReadAloud/{SystemSpeaker.swift（AVSpeechSynthesizer 实现 Speaker）,HttpSpeaker.swift（AVAudioPlayer 播放合成音频）,ReadAloudController.swift（AVAudioSession playback、MPRemoteCommandCenter、MPNowPlayingInfoCenter、定时）,ReadAloudPanel.swift（阅读器内朗读面板：播放 / 暂停 / 上下段 / 语速 / 定时 / 选择 TTS 源）}；project.yml 需要 UIBackgroundModes audio——你不能改 project.yml，请在报告里写明需要主会话在 project.yml 加 `UIBackgroundModes: [audio]` 的 Info.plist 项；Reader 接入（当前段高亮与自动翻页，最小改动逐处列出）。
3. 测试：状态机（播放 / 暂停 / 段推进 / 章末切章 / 定时停止）、HttpTTS 规则求值与缓存（ReplayHttpClient）、HttpTTS 实体解码与备份导入。
</task>
