# 实体与表兼容性

规格固定为 Kotlin `cb664b84d`，AppDatabase 版本 111，共 26 张实体表及 BookSourcePart 视图。下面覆盖 data/entities 下全部 Kotlin 文件；辅助模型不因位于该目录而单独建表。Swift 使用自己的迁移序列，新增迁移名为 `v7_entities`。

| Kotlin 实体或文件 | Swift 已有 | 缺失与本单元补齐理由 |
| --- | --- | --- |
| AutoTaskRule | 无 | 补全全部持久字段、auto_task_rules 与 Repository；不执行定时脚本。 |
| BaseBook | Book、SearchBook | 接口职责由值类型承担，不建表。 |
| BaseRssArticle | RssArticle、RssStar | 接口职责由值类型承担，不建表。 |
| BaseSource | BookSource、RssSource、HttpTTS | 接口职责由值类型承担，不建表。 |
| Book | Book、BookRow、books | 持久字段已有；复合 readConfig 保留 JSON。 |
| BookCacheInfo | Cache 模块 | 查询投影，不在 AppDatabase entities 中，不补表。 |
| BookChapter | BookChapter、BookChapterRow、chapters | 持久字段已有。 |
| BookChapterReview | ReviewRule | bookId、chapterId、summaryUrl 为辅助模型，未补模型，不补表。 |
| BookGroup | BookGroup、BookGroupRow、book_groups | groupId、groupName、cover、order、enableRefresh、show、bookSort、onlyUpdateRead 八字段已齐，无需迁移。 |
| BookHighlight | Reader/BookHighlight、highlights | 复用既有表与 Repository，补备份导入。 |
| BookMemo | 无 | 补 bookUrl、content、updatedAt、book_memos 与 Repository，不设置书架级联删除。 |
| BookProgress | Backup/BookProgressSync | 进度交换模型，不建表。 |
| BookSource | BookSource、BookSourceRow、book_sources | 持久字段已有。 |
| BookSourceChange | SourceEditingRepository | 修改操作辅助定义，不补表。 |
| BookSourceCheckState | CheckSource/BookSourceCheckState 为步骤报告，保存在 SourceStateRepository | 补 BookSourceCheckStateRow 的 bookSourceUrl、revision、sourceRevision、status、checkedAt、detail 及独立表与 Repository；保留现有步骤报告，设备局部状态不进入 Android 备份。 |
| BookSourcePart | BookSourceRepository | 查询投影由 Repository 提供，不复制 Room 视图。 |
| Bookmark | Bookmark、BookmarkRow、bookmarks | 持久字段已有。 |
| BookshelfBook | BookRow | 书架查询投影，派生展示字段不另建表。 |
| Cache | 无通用实体 | 补 key、value、deadline、caches 与 Repository；备份仅接受规定前缀的运行时缓存。 |
| Cookie | Cookie、CookieRow、cookies | 补 cookies.json 导入导出，保留 Android 的严格字符串字段校验。 |
| DictRule | DictRule、dictRules | 已有。 |
| HighlightRule | 无 | 补全部 13 字段、highlightRules 与 Repository；JSON order 对应数据库 sortOrder，uuid 唯一。 |
| HttpTTS | HttpTTS、httpTTS | 已有。 |
| KeyboardAssist | 无 | 补 type、key、value、serialNo、keyboardAssists 与 Repository，联合主键 type/key；恢复时整表替换，打开空表时载入指定提交的全部 32 项默认集合。 |
| ReadRecord | ReadRecord、ReadRecordRow、readRecord | 已有，snapshot 为派生状态。 |
| ReadRecordBook | ReadProgressRepository | bookName/author 查询投影，不补表。 |
| ReadRecordMerge | ReadProgressRepository | 合并逻辑，不是实体，不补表。 |
| ReadRecordShow | ReadProgressRepository | 聚合展示模型，不补表。 |
| ReplaceBook | SearchBook | 查询投影，不补表。 |
| ReplaceRule | ReplaceRule、ReplaceRuleRow、replace_rules | 已有，previewText 非持久字段。 |
| RssArticle | RssArticle、rssArticles | B11 的 v6 提供。 |
| RssReadRecord | RssReadRecord、rssReadRecords | B11 的 v6 提供。 |
| RssSource | RssSource、rssSources | B11 的 v6 提供。 |
| RssStar | RssStar、rssStars | B11 的 v6 提供。 |
| RuleSub | 无 | 补全部 12 字段、ruleSubs 与 Repository；保存 js/showRule/sourceUrl；脚本执行不在本单元范围。 |
| SearchBook | SearchBook、SearchBookRow、searchBooks | 已有。 |
| SearchKeyword | 无 | 补 word、usage、lastUseTime、search_keywords 与 Repository，并接入搜索历史。 |
| Server | 无 | 补 id、name、type、config、sortNumber、servers 与 Repository；WebDavConfig 的 url/username/password 保存为 Android JSON 字符串。 |
| TxtTocRule | TxtTocRule、txtTocRules | 已有。 |
| ReadRecordDetail | 指定 Kotlin 版本无此文件、类或实体表 | 不臆造实体或迁移。 |
| rule 子目录 | ExploreRule、SearchRule、BookInfoRule、TocRule、ContentRule、ReviewRule | 复合规则模型，不单独建表。 |

时间字段解码缺省值采用可注入时钟；StorageRow 手工初始化保持现有显式时间戳约定。RuleSub 类型仅接受界面实际使用的 0、1、2。缺省 ID 逐条分配，导入保存时遇到重复或零 ID 重新分配。

BookMemo 仅恢复本次成功恢复书籍的较新备注，包含清空后的时间戳记录。旧高亮保留已有 style，只在空白时转换 bgColor/textColor；空白归属通过书名作者、章节序号及标题匹配回填。高亮规则按 normalizeForRestore 规范化，校验 UUID 唯一后整表替换，并按导入顺序从 0 编号。恢复顺序为书架、备注、书签、高亮、高亮规则、书组，避免归属查询早于书架恢复。

备份以 Backup.kt selectedBackupFileNames 的完整清单为准，共 28 文件。额外配置文件原样保存在 backup_files 中，仅在存在时再次导出，不宣称已应用到 iOS 界面。cookies 与运行时缓存遵循默认不选中的行为，显式传入 includeSourceState 才导出明文 JSON。Android 的加密服务器与加密运行时缓存需要原有凭据，本单元支持明文 JSON，无法解密时报告文件失败。
