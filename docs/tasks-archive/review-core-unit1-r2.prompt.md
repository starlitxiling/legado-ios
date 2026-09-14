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
目标：对 RuleAnalyzer 返修后的实现做收窄复审：核对上一轮 7 条 finding 是否消除、修复是否引入新偏差，并对照刚补精确的规格 §3。
工作目录：/Users/wujie/Work/legado-ios/.claude/worktrees/ios（分支 ios）
背景与入口：代码 Packages/LegadoCore/Sources/LegadoCore/RuleAnalyzer.swift（216 行）与 Tests/LegadoCoreTests/RuleAnalyzerTests.swift（229 行，22 条测试，实现者报告全绿）。规格 docs/spec/rule-engine.md §3（已按 Kotlin 补精确，commit dffad6c7c，第 71-118 行）。Kotlin 只读 /Users/wujie/Work/legado-ios/app/src/main/java/io/legado/app/model/analyzeRule/RuleAnalyzer.kt（commit 2bdd3c58b）。上一轮 7 条：① 顶层引号不保护分隔符；② innerRule 单标记未闭合返回空串不抛错；③ 回调空串后从组尾再前进标记长度；④ consumeToAny / 两种平衡组失败恢复游标；⑤ splitRule 终点不强制串尾；⑥ UTF-16 偏移；⑦ trim 无跳过不改起点。另请特别核对两处规格补写后的细节：引号保护在 chompRuleBalanced 与 chompCodeBalanced 内都生效（Kotlin :105-108、:141-144）；splitRule 直接追加尾段时游标停在尾段起点、吞括号后的无候选分支保留闭括号后的位置（:199、:234-236、:293-296）。
约束：只读，不修改文件，不 commit，沙箱只读不要尝试编译。
完成标准：逐条给出 7 条状态；列出置信 ≥60 的新问题（文件绝对路径:行号、置信、具体输入下 Swift 与 Kotlin 的行为差异、建议）；没有就写 clean 并列出对照过的方法与输入。
汇报格式：中文 markdown ≤ 40 行。
</task>
