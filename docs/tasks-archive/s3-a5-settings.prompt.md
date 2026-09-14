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
目标：阶段 3 单元 A5 —— 设置与备份：WebDAV 账号（Keychain）、从 WebDAV 列出并恢复备份（只读：PROPFIND / GET）、本地 zip 导入、恢复结果展示、关于页。
工作目录：/Users/wujie/Work/legado-ios/.claude/worktrees/ios。工程骨架见 App/（project.yml 为真源，XcodeGen 按目录收集源文件，**不要运行 xcodegen、不要改 project.yml 与 Legado.xcodeproj**，新文件放进 App/Sources/Features/<功能>/ 即可）。已有：App/Sources/App/{LegadoApp,AppContainer,RootTabView,DatabaseLifecycleCoordinator}.swift、Features/Bookshelf、Shared/{Theme,EmptyStateView}；并行任务正在写 Features/Sources、ReplaceRules（A2）与 Features/Search、BookDetail、Toc（A3），不要碰这些目录，接口对接用 protocol 或导航值约定并在报告写明。LegadoCore（Packages/LegadoCore）提供 Entities、Storage Repositories（书架 / 章节 / 阅读进度 / 书签 / 替换规则）、WebBook（BookContent 取正文）、Content/ContentProcessor、Backup/WebDavBackupSource、WebDAV/WebDavClient、Network/BoundedURLSessionHttpClient、Import。ViewModel 与纯逻辑放在不 import UIKit / SwiftUI 的文件里，用 @Observable；单测走 tools/appcore-check（已有 SwiftPM 包，通过软链接引用 App 下不含 UI 的文件，追加自己的目标即可）。本机无 iOS 平台组件，你不能跑 xcodebuild。Swift 语言模式 5；不加第三方依赖；不 commit；不联网。
产出：
1. App/Sources/Shared/KeychainStore.swift（kSecClassGenericPassword 的读写删，service 固定，account 为字段名；无 UI 依赖，可用 protocol 抽象以便测试注入内存实现）。
2. App/Sources/Features/Settings/：SettingsViewModel（WebDAV url / 账号 / 密码的读写到 Keychain、连接测试只做 PROPFIND 根目录、阅读设置入口留给 A4、关于信息：版本号、开源许可列表含 SwiftSoup / Kanna / GRDB / PSL 的许可说明）、SettingsView。
3. App/Sources/Features/Backup/：BackupViewModel（列出远端 legado 目录备份：复用 WebDavBackupSource，只读；选择一份下载并用 BackupImporter 导入到应用数据库，展示每张表导入行数、跳过文件、失败文件；本地 zip 经 UIDocumentPicker 导入同流程；导入进行中不可重入；导入后发出通知让书架 / 书源列表刷新）、BackupView、RestoreResultView。**任何路径都不得调用 WebDavClient 的 put / mkcol / delete**；代码里给 WebDavBackupSource 传只读能力对象或在 ViewModel 层不暴露写方法。
4. RootTabView 的「设置」Tab 接入 SettingsView，备份入口在设置页。
5. 单测（appcore-check 新目标）：Keychain 内存实现下的账号读写；BackupViewModel 用 ReplayHttpClient 回放 PROPFIND + GET（复用 Tests/Conformance/fixtures/backup 的合成 zip）走完整恢复并断言行数；确认没有写请求发出（Replay 记录的请求方法集合只含 PROPFIND / GET）。
完成标准：同 A4。
汇报格式：中文 markdown ≤ 50 行。
</task>
