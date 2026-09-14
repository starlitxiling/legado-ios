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
目标：只读复审阶段 4 单元 B13「备份上传与设置对齐」的未提交改动（git diff HEAD 与未跟踪文件中属于 B13 的部分），对照 Kotlin（commit 2bdd3c58b，只读，前缀 /Users/wujie/Work/legado-ios/app/src/main/java/io/legado/app/）找出与 Android 行为 / 文件格式不一致、逻辑错误、并发缺陷、测试固化错误期望的问题；并**盘点设置项缺口**。工作目录 /Users/wujie/Work/legado-ios/.claude/worktrees/ios。
B13 范围（其他未提交改动属于并行的 B11 / B12 / B14 / B15，忽略）：Packages/LegadoCore/Sources/LegadoCore/Backup/{BackupExporter,AndroidPreferencesXML,WebDavBackupUploader,BookProgressSync}.swift、BackupImporter.swift 改动、WebDAV/WebDavClient.swift 改动；App/Sources/Features/Backup/{BackupView,BackupViewModel,BackupPreferences,BackupLifecycleModifier}.swift、Features/Settings/GeneralSettingsView.swift、SettingsView.swift:33、LegadoApp.swift:16、ReaderViewModel.swift:268 / ReaderView.swift:28 / DownloadCenterModel 的预下载与线程数接入；测试 BackupExportTests、BackupTests、BackupPreferenceTests、WebDavTests、tools/appcore-check/check-b13.sh。
Kotlin 对照点：help/storage/Backup.kt（backupFileNames 全清单与顺序、每个 JSON 的序列化方式、config.xml / videoConfig.xml 的 SharedPreferences XML 结构与 ignoreKeys、备份文件名 backupyyyy-MM-dd[-设备名].zip 的确切拼法与设备名来源、本地 backup.zip、autoBackup 触发条件与 lastBackup 记录）、help/storage/Restore.kt（恢复顺序、偏好恢复时的类型校验与跳过键）、help/AppWebDav.kt（backUpDir 路径 legado、MKCOL 时机、PUT 覆盖、getBackupNames 排序、bookProgress 上传文件名 bookProgress/<name>.json 与 JSON 字段、downloadBookProgress 比较逻辑 :320/:325、同步期间新阅读的保护）、lib/webdav/WebDav.kt（PROPFIND depth、exists 判定、PUT 的 Content-Type 与 Overwrite）、help/config/AppConfig.kt（设置项全集：列出 Android 有而 Swift GeneralSettingsView / 既有 Settings 页缺失的 key，按 ThemeConfig / OtherConfig / BackupConfig 三组分类，给出缺失清单）。
方法：先 git status / git diff 定位 B13 文件；每个 finding 给 Swift 文件绝对路径:行号 与 Kotlin 文件:行号 依据；标 P1/P2/P3 与置信度；只报告确有依据的问题，不报告风格。缺失设置项清单单独一节列出 key 名与 Kotlin 位置。不修改任何文件、不运行 xcodegen / xcodebuild、不在 /tmp 做副本；读代码为主，不必跑测试；**不得对任何真实 WebDAV 服务器发请求**。
交付：中文 markdown ≤ 60 行；无问题则明确写 clean 并说明抽查了哪些对照点。
</task>
