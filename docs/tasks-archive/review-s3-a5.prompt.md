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
目标：独立复审阶段 3 单元 A5（Keychain、设置、WebDAV 备份恢复、关于页）。
工作目录：/Users/wujie/Work/legado-ios/.claude/worktrees/ios（分支 ios）
背景与入口：新文件（未跟踪）App/Sources/Shared/KeychainStore.swift、Features/Settings/{SettingsViewModel,SettingsView,OpenSourceLicense}.swift、Features/Backup/{BackupViewModel,BackupView,RestoreResultView}.swift、RootTabView 的 backupRestored 通知、tools/appcore-check 的 SettingsBackupCheck 目标。依赖 LegadoCore 的 Backup/{WebDavBackupSource,BackupImporter}、WebDAV/WebDavClient、Network/BoundedURLSessionHttpClient。硬约束：**任何路径不得对真实服务器发起 PUT / MKCOL / DELETE / MOVE / COPY**（只读账号）。
审查角度：① 安全：grep Features/Backup、Features/Settings、Shared/KeychainStore 与其调用的 LegadoCore 入口，确认不会触达 WebDavClient 的写方法；Keychain 项的 accessibility 属性（建议 kSecAttrAccessibleAfterFirstUnlock）、更新时先删后写还是 SecItemUpdate、错误码处理；密码不进日志 / UserDefaults；② 连接测试的 PROPFIND Depth 0 与 Basic 认证；③ 备份恢复：导入期间数据库写事务与 UI 刷新的顺序、防重入、256 MiB 上限、本地 zip 的 security-scoped resource 访问（startAccessingSecurityScopedResource）、临时文件清理、导入后 Legado.backupRestored 通知的时机（导入事务提交后）；④ 结果页字段与 BackupImporter 报告的对应；⑤ 关于页许可文本来源是否为本地 checkouts 的 LICENSE 原文；⑥ 测试是否迁就实现、请求方法集合断言是否严格。
约束：只读，不修改文件，不 commit，不编译。
完成标准：finding 列表（文件绝对路径:行号、置信 0-100、问题与建议），< 60 不列；安全项单独给结论。没有其他问题就写 clean。
汇报格式：中文 markdown ≤ 45 行。
</task>
