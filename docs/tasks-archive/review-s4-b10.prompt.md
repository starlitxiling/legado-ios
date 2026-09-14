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
目标：只读复审阶段 4 单元 B10「书架进阶与下载」的未提交改动（git diff HEAD 与未跟踪文件中属于 B10 的部分），对照 Kotlin（commit cb664b84d，只读，前缀 /Users/wujie/Work/legado-ios/app/src/main/java/io/legado/app/）找出与 Android 行为不一致、逻辑错误、并发 / actor / 生命周期缺陷、测试固化错误期望的问题。工作目录 /Users/wujie/Work/legado-ios/.claude/worktrees/ios。
B10 范围（其他未提交改动属于并行的 B8 / B9，忽略）：Packages/LegadoCore/Sources/LegadoCore/Cache/{CacheBook,BookshelfRefresh,BookHelp,BookExporter}.swift、Storage/Repositories/{BookshelfAdvancedRepository,BookshelfRepository}.swift 改动；App/Sources/Features/Bookshelf/{GroupEditView,BookshelfBackgroundRefresh}.swift 与 BookshelfViewModel 局部改动、Features/BookDetail/Edit/、Features/Download/、AppContainer.swift 局部改动、Reader/ReaderChapterCache.swift 两处插入；测试 LegadoCoreTests/BookshelfAdvancedTests、appcore-check BookshelfAdvancedCheckTests。
Kotlin 对照点：data/entities/BookGroup.kt 与 constant/AppConst（内置分组 id：全部 -1、本地 -2、音频 -3、网络 -4、未分组 -5、更新失败 -11 等，回源核对确切常量与位运算 groupId 的多分组语义）、ui/book/group/GroupViewModel.kt 与 data/dao/BookGroupDao.kt（order 计算、删除分组时书籍 groupId 处理）、model/CacheBook.kt 与 service/CacheBookService.kt（并发数来自 AppConfig.threadCount、按书源 concurrentRate 限速、失败重试次数与 onError 语义、章节已缓存跳过、成功 / 失败 / 进度回调、取消时清理）、help/book/BookHelp.kt（章节文件名 formatChapterName：index 补零位数与标题净化规则、hasContent、图片子目录、书名改动时的目录迁移）、ui/book/cache/CacheViewModel.kt 与 help/book/BookExport（TXT 导出：标题行格式、章节间换行、替换规则应用与 useReplaceRule、导出目录与文件名；EPUB：mimetype stored 首项、container.xml、OPF 的 metadata / manifest / spine / guide、封面 xhtml、章节 xhtml 转义与段落 <p> 包裹、目录 toc.ncx / nav）、ui/main/MainViewModel.kt upToc（并发上限、单书失败不影响其他、更新后 latestChapterTime / lastCheckCount 字段）、ui/book/info/edit/BookInfoEditViewModel.kt（保存时哪些字段覆盖、封面自定义 customCoverUrl 语义）。
方法：先 git status / git diff 定位 B10 文件；每个 finding 给 Swift 文件绝对路径:行号 与 Kotlin 文件:行号 依据；标 P1/P2/P3 与置信度；只报告确有依据的问题，不报告风格。不修改任何文件、不运行 xcodegen / xcodebuild、不在 /tmp 做副本；读代码为主，不必跑测试。
交付：中文 markdown ≤ 50 行；无问题则明确写 clean 并说明抽查了哪些对照点。
</task>
