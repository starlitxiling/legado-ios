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
目标：把规则引擎规格 §3（RuleAnalyzer 切分算法）中 5 处不够精确、已导致 Swift 实现偏离 Kotlin 的条文补写精确，使实现者只读规格就能得到与 Kotlin 逐字节一致的行为。
工作目录：/Users/wujie/Work/legado-ios/.claude/worktrees/ios（只能修改 docs/spec/rule-engine.md；不 commit）
背景与入口：Kotlin 源码只读 /Users/wujie/Work/legado-ios/app/src/main/java/io/legado/app/model/analyzeRule/RuleAnalyzer.kt（377 行，commit cb664b84d）。规格顶部 commit 标注保持不变。要补精确的 5 处（行号为当前规格行号）：
1. 第 71、78、80 行：游标与位置的编码语义。Kotlin 按 UTF-16 char 索引（RuleAnalyzer.kt:37、57、79）；补一句「所有位置、步长、长度均按 UTF-16 code unit 计，补充平面字符占 2」，并加一个 emoji 示例。
2. 第 79、81、82 行：consumeToAny / chompRuleBalanced / chompCodeBalanced 失败时游标恢复到调用前（Kotlin :51、:93、:133），成功时游标停在何处；逐方法写清返回值与游标后置条件。
3. 第 90、99、101 行：splitRule 各分支结束时的游标位置（有分隔符：停在最后一个分隔符之后的段末，Kotlin :169、:194、:199；无分隔符：保持调用前位置），以及「无分隔符不检查未闭合括号」的确切条件。
4. 第 109 行：引号保护只在 chompCodeBalanced 内生效，顶层切分不受引号影响（Kotlin :185、:194）；给 'a||b'||c → ["'a","b'","c"] 示例。
5. 第 114 行：innerRule 的两种重载各自的失败行为（单标记未闭合：跳过标记、返回空串而不是错误，Kotlin :318、:326）与回调返回空串后的续搜起点（从闭合后的游标再前进标记长度，:123），给 {$.a}{$.b} 示例。
另：第 77 行 trim 只在实际跳过前导字符时更新起点（Kotlin :16、:19），补一句。
约束：只改这些条文与直接关联示例，每条附 RuleAnalyzer.kt 行号；不重排其他段落；改动后规格总行数变化不超过 +30。
完成标准：逐条给出修改后的规格行号与 Kotlin 行号；跑 wc -l 与 grep -c "\.kt:[0-9]" 贴结果。
汇报格式：中文 markdown ≤ 30 行。
</task>
