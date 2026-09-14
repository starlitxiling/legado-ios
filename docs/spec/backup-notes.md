# 备份恢复与 WebDAV

规格基线为 Kotlin `2bdd3c58b` 的 Restore、ReadRecordMerge、WebDav 与 AppWebDav。

## 支持与跳过

- 按顺序恢复 `bookshelf.json`、`bookmark.json`、`bookGroup.json`、`bookSource.json`、`replaceRule.json`、`readRecord.json`。
- JSON 经现有 Gson 兼容实体解码；书源经过 SourceImporter，复合规则及 readConfig 存为数据库 JSON 文本。
- RSS（Kotlin 文件名为 `rssSources.json`）、txtTocRule、httpTTS、dictRule、config.xml、媒体与其他文件均跳过并记录文件名。
- 加密 Cookie、服务器凭据、运行态变量、Android 配置与媒体路径迁移不在本单元实现范围内。
- `searchHistory.json` 在 Restore.kt:353 导入 SearchKeyword，`highlightRule.json` 在 :319 规范化后整表替换；Swift 尚无对应实体/表，本单元记录跳过，不代表 Kotlin 忽略它们。
- `readRecordDetail.json`、`webSearchEngines.json` 在基线 Restore.kt 中没有恢复入口，因此本单元跳过；不将搜索历史误导入 SearchBook 缓存表。
- 单个 JSON 解析或落库失败会记入 failures，继续其他文件；同一文件的数据库操作在事务内完成。
- GsonExtensions.fromJsonArray 对整份 List 解码；单条记录失败或出现 null 元素使整文件失败，Swift 同样不逐条跳过。

## 冲突策略

- 书架同 URL 更新并保留章节；名称与作者唯一键冲突时按 Room REPLACE 替换旧书。
- 书源、分组、书签、替换规则按主键覆盖，备份外的本地记录保留。
- 替换规则 id=0 按 Room 自增，非零重复 ID 按 REPLACE；导入计数为该文件最终涉及的不同数据库行数。
- previewText 被 Kotlin Room @Ignore 排除，由 ReplacePreviewConfig 保存；Swift 尚无对应配置存储，已知丢失通过报告 discardedFields 标出；其他实体字段均已存入 Row。U5 无必补的 Room 列，需另补预览配置存储。
- 阅读记录空设备 ID 归调用方明确提供的本机 ID；本机累计时长取最大值，其他设备使用备份时长。
- 阅读快照按较新 lastRead 合并，缺章节或封面时回退旧快照，保留已有 resolvedAuthor。
- 不恢复不存在的旧版书源字段映射；无法被现有实体接受的文件记入 failures。

## ZIP 与 WebDAV

- 最小 ZIP 读取器使用中央目录，支持 stored、Compression 原始 DEFLATE 和 data descriptor；仅在内存解包。
- DEFLATE 持续读取至 END；输入耗尽后继续排出内部缓冲，拒绝无进展、超量输出和尾随压缩数据；本地头为零的大小由中央目录提供。
- 校验 CRC、路径、重复名称与展开总量（默认 256 MiB）；拒绝加密、ZIP64、多卷及其他压缩格式。
- WebDAV 经 HttpClient 注入；Basic 默认 ISO-8859-1，与 Kotlin 一致；凭据选择由上层完成。
- PROPFIND Depth 为 1，exists 为 0；解析 DAV 命名空间、成功 propstat、collection 与 httpd/unix-directory。
- 坚果云百分号编码 href 直接作为 URL 解析；显示名解码一次，保留加号，避免文件名二次编码。
- 默认列举服务根下 legado 目录，筛选 backup 或 legado 前缀的 .zip；日期优先，其次服务器修改时间，最后自然名称降序。
- Kotlin AppWebDav 仅筛选 backup 前缀；legado 前缀按本单元需求扩展支持。
- 独立 tools/webdav-smoke 只列举和下载，写入临时文件并恢复至内存数据库，不修改真实远端。
- 下载默认上限 256 MiB，列表大小先检查；使用 ResponseLimitedHttpClient 在响应头及分块读取时限量并取消任务。生产调用方需注入 BoundedURLSessionHttpClient，旧客户端未实现限流接口时拒绝下载。
- 冒烟环境变量为 LEGADO_WEBDAV_URL、LEGADO_WEBDAV_USER、LEGADO_WEBDAV_PASSWORD；URL 指向 legado 的父目录。
- 在仓库根运行 `swift run --package-path tools/webdav-smoke WebDavSmoke`；临时备份路径打印后由调用方清理。
