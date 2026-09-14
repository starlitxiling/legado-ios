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
目标：独立复审阶段 4 单元 B3（本地书 TXT / EPUB：导入、编码探测、TxtTocRule 分章与内置规则、偏移读取、EPUB 解析、书架与阅读器接入、TXT 目录规则管理）。
工作目录：/Users/wujie/Work/legado-ios/.claude/worktrees/ios（分支 ios）
背景与入口：新增 Packages/LegadoCore/Sources/LegadoCore/LocalBook/{LocalBook,TextFileParser,TxtTocRule,EpubParser,ZipReader}.swift、Storage 的 v2 迁移与 TxtTocRule 仓库、WebBook.swift 的本地分流；App/Sources/Features/LocalImport/*、TXT 目录规则页、BookshelfView 入口；测试 LocalBookTests / EpubParserTests / 编码与迁移测试、appcore-check 的导入与阅读测试。Kotlin 只读（commit 2bdd3c58b）：/Users/wujie/Work/legado-ios/app/src/main/java/io/legado/app/model/localBook/{LocalBook,TextFile,EpubFile,EpubToc}.kt、data/entities/TxtTocRule.kt、help/DefaultData.kt 与 app/src/main/assets/defaultData/txtTocRule.json（26 条内置规则的 name / rule / example / serialNumber / enable）、utils/EncodingDetect.kt、help/book/BookHelp.kt（本地书章节缓存与 getContent）、constant/AppPattern.kt（nameAuthor 正则）。
审查角度：① 文件名解析（书名 / 作者的正则与分隔）、origin / type 位、bookUrl 形式与 Kotlin 一致；② TXT：编码探测顺序（BOM、GBK / UTF-8 判定、EncodingDetect 的启发式）、分块扫描的边界（章节标题跨块）、规则匹配的多行模式与 Kotlin 一致、无匹配时的默认规则与「单章回退」、章节 start / end 偏移与 getContent 读取（含跨块）、超大文件内存；③ 内置规则 26 条逐条与 assets 原文一致（rule 正则字符串是否逐字，serialNumber 与 enable）、正则方言（Java 与 ICU 差异：\s、行首 ^ 多行）；④ EPUB：OPF 路径解析（container.xml → rootfile）、spine 与 manifest 的 href 解码、NCX 与 nav 优先级、锚点分割章节、正文 HTML → 文本的段落与图片占位、封面识别、损坏 zip 的修复路径；⑤ 迁移 v2 幂等与 v1 数据不受影响；⑥ App：security-scoped bookmark 持久化与复制策略、重复导入判定；⑦ 测试是否迁就实现、样本是否自造。
约束：只读，不修改文件，不 commit，不编译。
完成标准：finding 列表（文件绝对路径:行号、置信 0-100、问题与建议），< 60 不列；没有就写 clean。
汇报格式：中文 markdown ≤ 50 行。
</task>
