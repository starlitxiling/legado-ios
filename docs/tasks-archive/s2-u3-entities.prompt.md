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
目标：阶段 2 单元 U3 —— 在 LegadoCore 建立 MVP 所需实体的 Codable 模型与书源 / 替换规则 JSON 导入解析，对齐 Kotlin 的 Gson 宽松反序列化语义。
工作目录：/Users/wujie/Work/legado-ios/.claude/worktrees/ios（可写：Packages/LegadoCore/Sources/LegadoCore/Entities/、Sources/LegadoCore/Import/（新目录）、Tests/LegadoCoreTests/ 新文件、Tests/Conformance/fixtures/import/（新，合成 JSON）；不得改 Package.swift（另一任务在改）与既有目录、既有测试；不加依赖；不 commit）
背景与入口（Kotlin 为规格，只读，commit 2bdd3c58b）：
- 实体：/Users/wujie/Work/legado-ios/app/src/main/java/io/legado/app/data/entities/BookSource.kt（357 行，字段与默认值）、data/entities/rule/{SearchRule,ExploreRule,BookInfoRule,TocRule,ContentRule,ReviewRule}.kt、BaseSource.kt（header / loginUrl / jsLib 等共有字段）、ReplaceRule.kt、Book.kt、BookChapter.kt、SearchBook.kt、BookGroup.kt、Cookie.kt、ReadRecord.kt、Bookmark.kt。只做 MVP 需要的字段，Room 注解、Parcelable、UI 相关方法忽略；每个实体字段的默认值必须与 Kotlin 一致。
- 反序列化容错：utils/GsonExtensions.kt（:49-54 为 6 个 Rule 类注册的 jsonDeserializer：既接受对象也接受 JSON 字符串；StringJsonDeserializer :140、IntJsonDeserializer :159 的弱类型规则：数字 / 布尔 / 字符串互转、null 处理）、rule/SearchRule.kt:29-35。
- 导入入口：ui/association/BookSourceImport.kt:88 parseBookSourceJson（source 数组 / 单对象 / url 数组）、ImportBookSourceViewModel.kt:277-290（非 JSON 文本判为纯 JS 书源 JsSourceConfig.extract——本单元只识别并返回「不支持」标记）；ReplaceRule 导入同理（ui/replace 下的导入逻辑）。
- 合规约束（PLAN §7）：仓库内不得出现真实书源、站点 URL、站名；测试用自造 JSON，域名一律 example.invalid。
产出：
1. Entities/*.swift：上述实体的 Codable struct，每个字段注明 Kotlin 默认值；规则对象实现自定义 Decodable：接受对象或 JSON 字符串；字段级弱类型（Int 接受 \"12\" / 12.0 / true；String 接受数字 / 布尔并按 Gson 规则转成字符串；null → 默认值）。
2. Import/SourceImporter.swift：parseBookSources(text) → 枚举结果（sources / urls / jsSource(unsupported) / invalid）；parseReplaceRules(text)。
3. 测试：TDD 先红后绿；fixtures/import/ 下自造 JSON 覆盖：完整书源、规则为字符串写法、弱类型字段、缺字段取默认、url 数组、单对象、非法文本、纯 JS 文本；round-trip（decode → encode → decode 等价）。
约束：Swift 6.0 工具链、语言模式 5；不 commit。
完成标准：同样命令跑全量 swift test（并行任务半成品导致编译失败时用隔离副本并说明）；报告附命令与末尾 15 行原始输出、测试总数、实体字段清单与默认值来源行号、导入分支明细。
汇报格式：中文 markdown ≤ 60 行。
</task>
