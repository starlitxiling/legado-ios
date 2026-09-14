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
目标：独立复审阶段 4 单元 B6（听书：ReadAloudEngine 状态机、HttpTTS 源与合成缓存、实体 / 表 / 备份导入、系统与 HTTP 播放适配、音频会话与远程控制、阅读器联动）。
工作目录：/Users/wujie/Work/legado-ios/.claude/worktrees/ios（分支 ios）
背景与入口：新增 Packages/LegadoCore/Sources/LegadoCore/TTS/{ReadAloudEngine,HttpTTSSource}.swift、Entities/HttpTTS.swift、Storage 的 HttpTTS 表与 v3 迁移（Migrations.swift:202）、BackupImporter.swift:32 / :71 的 httpTTS.json 导入；App/Sources/Features/ReadAloud/{SystemSpeaker,HttpSpeaker,ReadAloudController,ReadAloudPanel,…}.swift、ReaderViewModel.swift:30 与 ReaderView.swift:9 的联动；测试 ReadAloud* 与 ReaderTests 相关用例。Kotlin 只读（commit 2bdd3c58b）：/Users/wujie/Work/legado-ios/app/src/main/java/io/legado/app/service/{BaseReadAloudService,TTSReadAloudService,HttpReadAloudService}.kt、data/entities/HttpTTS.kt、help/storage/Restore.kt（httpTTS.json 顺序）、model/ReadAloud.kt（入口与状态广播）、ui/book/read/ReadAloudDialog.kt、help/config/AppConfig.kt（ttsSpeechRate、readAloudByPage 等）。
审查角度：① 状态机与 Kotlin 逐分支：播放起点（当前页首段还是当前段）、readAloudByPage 模式、段落切分规则（按换行 / 句号？回源 BaseReadAloudService 的 contentList 生成）、暂停 / 恢复位置、章末自动切章与预加载、定时停止的到期行为、失效回调；② HttpTTS：url 规则求值时的绑定（speakText / speakSpeed 的内插与 Kotlin 一致：语速是 AppConfig 的值经何种换算）、并发预合成数与 concurrentRate、缓存文件命名与清理、contentType 与非音频响应的错误处理、loginCheckJs 未支持的影响面、失败重试次数；③ 实体字段与默认值、备份导入顺序与冲突策略；④ App：AVAudioSession 类别与选项（playback、mixWithOthers？回源 Kotlin 的音频焦点策略）、中断 / 耳机拔出后的恢复策略、MPRemoteCommandCenter 命令集合、NowPlaying 信息、后台任务保活；⑤ 阅读器联动：当前段高亮的偏移计算与 durChapterPos 更新时机、自动翻页；⑥ 测试是否迁就实现。
约束：只读，不修改文件，不 commit，不编译。
完成标准：finding 列表（文件绝对路径:行号、置信 0-100、问题与建议），< 60 不列；没有就写 clean。
汇报格式：中文 markdown ≤ 50 行。
</task>
