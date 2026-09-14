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
目标：只读复审阶段 4 单元 B15「实体与表补齐」的未提交改动（git diff HEAD 与未跟踪文件中属于 B15 的部分），对照 Kotlin（commit 2bdd3c58b，只读，前缀 /Users/wujie/Work/legado-ios/app/src/main/java/io/legado/app/）找出实体字段 / 主键 / 默认值与 Android 不一致、备份文件清单与 Restore 顺序不一致、迁移缺陷、测试固化错误期望的问题；并核对 docs/spec/entities-compat.md 的对照表是否遗漏实体。工作目录 /Users/wujie/Work/legado-ios/.claude/worktrees/ios。
B15 范围（其他未提交改动属于并行的 B11 / B12 / B13 / B14，忽略）：Packages/LegadoCore/Sources/LegadoCore/Entities/{SearchKeyword,HighlightRule,RuleSub,Server,KeyboardAssist,Cache,AutoTaskRule,BookMemo,ReadRecordDetail 等新增}.swift、Storage/EntityCompatibilityMigration.swift（v7_entities）、Storage/Rows/BookSourceCheckStateRow.swift、Repositories/CompatibilityRepositories.swift、Backup/{BackupFileManifest,BookHighlightDecoding}.swift 与 BackupImporter / BackupExporter 改动、Import/RuleSubImporter.swift；App/Sources/Features/Settings/{SubscriptionSettingsModel,RuleSubSettingsView,ServerSettingsView}.swift、SearchViewModel.swift:39 / SearchView.swift:14；docs/spec/entities-compat.md；测试 EntityCompatibilityTests、appcore-check EntitySettingsCheckTests。
Kotlin 对照点：data/AppDatabase.kt 的 entities 数组（先 ls data/entities 列全量，逐个核对 Swift 是否有对应）、每个实体的 @PrimaryKey / 索引 / 默认值（SearchKeyword.word 主键与 usage / lastUseTime；RuleSub 的 type 枚举与 customOrder、autoUpdate、update 时间；Server 的 config JSON 结构与 type；KeyboardAssist 的 type / key / value 与默认集合 help/DefaultData 的 keyboardAssists；Cache 的 key / value / deadline；HighlightRule 若存在；ReadRecord / ReadRecordDetail 的 deviceId、readTime、lastRead；BookSource 校验元数据 checkState 等）、help/storage/Backup.kt backupFileNames 全清单与 Restore.kt 的恢复顺序（28 项逐一对照）、ui/rss/subscription/RuleSubViewModel.kt 与 ui/association 的 RuleSub 导入（type 0 书源 / 1 RSS / 2 替换规则 的分派与从 URL 拉取）、utils/JsonExtensions 对老格式高亮的兼容解码。
方法：先 git status / git diff 定位 B15 文件；每个 finding 给 Swift 文件绝对路径:行号 与 Kotlin 文件:行号 依据；标 P1/P2/P3 与置信度；只报告确有依据的问题，不报告风格。遗漏实体单独一节列出。不修改任何文件、不运行 xcodegen / xcodebuild、不在 /tmp 做副本；读代码为主，不必跑测试。
交付：中文 markdown ≤ 50 行；无问题则明确写 clean 并说明抽查了哪些对照点。
</task>
