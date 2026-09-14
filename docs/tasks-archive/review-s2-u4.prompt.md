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
目标：独立复审阶段 2 单元 U4（WebBook 搜索 / 发现、详情、目录、正文四条流程与 ContentProcessor）是否逐分支对齐 Kotlin，并核查实现者声称「缺少 Kotlin 规格」的 checkKeyName。
工作目录：/Users/wujie/Work/legado-ios/.claude/worktrees/ios（分支 ios）
背景与入口：新文件（未跟踪）Packages/LegadoCore/Sources/LegadoCore/WebBook/{BookList,BookInfo,BookChapterList,BookContent,WebBook}.swift、Content/ContentProcessor.swift、Tests/LegadoCoreTests/WebBookTests.swift、Tests/Conformance/fixtures/webbook/。Kotlin 只读（commit 2bdd3c58b）：/Users/wujie/Work/legado-ios/app/src/main/java/io/legado/app/model/webBook/{BookList,BookInfo,BookChapterList,BookContent,WebBook}.kt、help/book/ContentProcessor.kt、help/book/ContentHelp.kt、data/entities/rule/*.kt、model/analyzeRule/AnalyzeRule.kt 中 setContent / setBaseUrl / setRedirectUrl 的用法、help/config/AppConfig.kt（搜索时的作者 / 书名过滤开关）、data/entities/BookSource.kt 与 BaseSource.kt（checkKeyName 是否是书源 ruleSearch 字段或 BookList 内部逻辑：请 grep 全仓 checkKeyName 找到定义与用法，给出行号，判断实现者「缺少规格」的说法是否成立）。实现者报告：单书回退、详情 URL 模式、名称作者过滤、URL 规范化、去重倒序、目录连续 / 列表分页与循环终止、卷与 VIP / 购买标记、gInt 标题格式化、正文分页与重复页停止、全文源级替换、替换规则作用域与 Java 捕获模板、超时非正回退 3000ms；繁简转换与重新分段留桩；WebView 正文报未支持。
审查角度：① BookList：ruleSearch.bookList 为空时的单书解析、checkKeyName / 名称作者过滤的真实语义（含 AppConfig 开关与 SearchBook 的 kind / wordCount / latestChapterTitle 填充）、bookUrl 规范化（NetworkUtils.getAbsoluteURL 与 baseUrl / redirectUrl）、去重键、发现页 exploreUrl 的 {{page}} 与 searchPage；② BookInfo：canReName、tocUrl 为空回退 bookUrl、字段覆盖策略（已有非空不覆盖）、downloadUrls；③ BookChapterList：nextTocUrl 多值（列表规则）与单值的处理顺序、循环终止条件（与已访问 URL 集合比对）、reverseToc、章节 index 与 title 的 formatJs 共享变量 gInt / gTitle、去重规则（同 URL 还是同 title）、isVolume / isVip / isPay 标记、updateTime；④ BookContent：nextContentUrl 循环终止（与本页 URL 或上一页相同、与下一章 URL 相同）、正文拼接分隔、replaceRegex 在分页拼接前后哪个阶段、title 处理、imageStyle / payAction、章节为 VIP 且内容为空时的行为；⑤ ContentProcessor：替换规则 scope 匹配（书名 / 作者 / 书源）、标题与正文分别应用、Kotlin 正则替换模板 $1 与 Java 语义、超时后是否禁用规则（Kotlin 的实际行为）、去重段落、缩进；⑥ 测试是否迁就实现、fixture 是否含真实站点。
约束：只读，不修改文件，不 commit，不编译。
完成标准：finding 列表（文件绝对路径:行号、置信 0-100、具体输入下的差异、建议），< 60 不列；checkKeyName 的结论单独给出。没有其他问题就写 clean 并列出对照过的分支。
汇报格式：中文 markdown ≤ 60 行。
</task>
