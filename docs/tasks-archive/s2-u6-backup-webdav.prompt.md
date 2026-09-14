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
目标：阶段 2 单元 U6 —— Legado 备份包解析与导入落库，以及 WebDAV 客户端（经 HttpClient 注入）；测试全部用假客户端。真实服务器只读冒烟由主会话另行执行，你不要联网。
工作目录：/Users/wujie/Work/legado-ios/.claude/worktrees/ios（可写：Packages/LegadoCore/Sources/LegadoCore/Backup/、Sources/LegadoCore/WebDAV/（新目录）、Tests/LegadoCoreTests/ 新文件、Tests/Conformance/fixtures/backup/（新，自造备份包）、docs/spec/backup-notes.md（新）；不得改 Package.swift、Network/、Entities/、Import/、Storage/ 既有文件、WebBook/（另一任务在写）与既有测试；不 commit）
背景与入口（Kotlin 为规格，只读，commit 2bdd3c58b）：/Users/wujie/Work/legado-ios/app/src/main/java/io/legado/app/help/storage/{Backup,Restore,BackupConfig}.kt（备份包内容：bookshelf.json、bookSource.json、rssSource.json、replaceRule.json、txtTocRule.json、readRecord.json、bookmark.json、httpTTS.json、dictRule.json、config.xml 等；zip 文件名 backup 与 legado 前缀规则、恢复顺序、字段兼容）、lib/webdav/{WebDav,WebDavFile,Authorization}.kt（PROPFIND 深度 1 解析 multistatus XML、GET 下载、PUT 上传、MKCOL、exists、Basic 认证、URL 编码、坚果云等服务器的兼容注意）、help/AppWebDav.kt（默认目录 legado、备份文件命名 backup{date}.zip 与 legado 前缀、按 serverID 选凭据）。
已有 Swift：HttpClient / URLSessionHttpClient / ReplayHttpClient、Entities（15 个模型，Import/SourceImporter）、Storage Repository（书架 / 章节 / 书源 / 替换规则 / 阅读进度 / 书签 / 分组 / Cookie）。zip 解包：不加第三方依赖，用 Foundation 可用的方式（若 Foundation 无原生 zip API，则自实现最小 zip 读取器：仅 stored 与 deflate 两种方法，deflate 用 Compression 框架），并在报告写明选择。
产出：
1. Backup/BackupArchive.swift（zip 读取）、Backup/BackupImporter.swift（解析各 JSON → 经 Import / Entities 解码 → 调 Storage Repository 落库；顺序与冲突策略按 Restore.kt；不识别的文件跳过并记录）。
2. WebDAV/{WebDavClient,WebDavFile,WebDavXMLParser}.swift：propfind(depth 1) / get / exists / put / mkcol；**本单元的测试与任何示例都不得调用 put / mkcol / delete 指向真实服务器**；Basic 认证头；URL 路径编码规则对齐 Kotlin；multistatus 解析容忍坚果云返回的命名空间与 href 编码。
3. Backup/WebDavBackupSource.swift：列出远端 legado 目录下的备份文件（按 Kotlin 命名规则过滤并按时间排序）、下载指定备份到内存 / 临时文件、交给 BackupImporter。
4. tools/webdav-smoke/ 下一个 Swift 脚本或 swift run 可执行目标（放在 Packages/LegadoCore 之外的独立 SwiftPM 可执行包 tools/webdav-smoke/Package.swift，依赖本地路径 ../../Packages/LegadoCore）：读取环境变量 LEGADO_WEBDAV_URL / LEGADO_WEBDAV_USER / LEGADO_WEBDAV_PASSWORD，只做 PROPFIND 与 GET（列出 legado 目录、下载最新备份到临时目录、跑 BackupImporter 到内存数据库、打印各表行数），代码里不得出现 put / mkcol / delete 调用。主会话会用 .env.local 里的凭据运行它。
5. 测试：TDD 先红后绿；fixtures/backup/ 自造一个含书源 / 书架 / 替换规则 / 阅读进度 / 书签的备份 zip（用脚本生成并提交生成脚本与产物）；WebDAV 用 ReplayHttpClient 回放 PROPFIND multistatus（含坚果云风格 XML）与 GET。
6. docs/spec/backup-notes.md（中文 ≤ 40 行）：支持的备份文件清单、跳过项、冲突策略、WebDAV 兼容注意。
约束：Swift 6.1 工具链、语言模式 5；不联网；不 commit。
完成标准：同样命令在工作区跑全量 swift test（并行任务半成品导致失败时用隔离副本并说明）；报告附命令与末尾 15 行原始输出、测试总数、冒烟工具的运行方式、zip 方案说明。
汇报格式：中文 markdown ≤ 65 行。
</task>
