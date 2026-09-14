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
目标：对 Claude Code 指令规则文件的改动做只读 review，找出会导致规则自相矛盾、事实错误或危险动作的问题。
工作目录：/Users/wujie/Work/legado-ios（git 分支 master）
背景与入口：待审改动 = `git diff`（CLAUDE.md 的修改）加上未跟踪的 `.claude/agents/*.md`（5 个文件，用 `git status --porcelain --untracked-files=all` 列出）。CLAUDE.md 是给 Coding Agent 读的项目规则；`.claude/agents/*.md` 是 Claude Code 的子 agent 定义（YAML frontmatter：name / description / model / effort / disallowedTools / color，其后为系统提示正文）。全局规则在 /Users/wujie/.claude/CLAUDE.md，全局 agent 定义在 /Users/wujie/.claude/agents/（本仓库的三个同名文件是它们的覆盖版，只改了 model 与 effort）。相关 skill：/Users/wujie/.claude/skills/codex-subagent/SKILL.md、/Users/wujie/.claude/skills/review-loop/SKILL.md。Codex 模型标识来自 /Users/wujie/.codex/config.toml。
已定前提（对这些的质疑不算问题）：用户钉死子 agent 只允许 Opus@high 或 Codex gpt-6-astra@medium；用户要求主会话只统筹、执行全委派、用进度文件断点续传；gpt-6-astra@medium 已实测可用。
审查角度：① 新规则与同文件其他段落、与全局 CLAUDE.md、与 review-loop skill 是否冲突（例如 review-loop 说不要传 model 入参，本规则靠 agent 定义钉死是否自洽）；② 事实性断言是否成立（Agent 工具是否真无 effort 入参；agent 定义是否会话启动时快照；frontmatter 字段名是否与全局定义一致；覆盖版三个文件除 model/effort 外是否与全局逐字一致，用 diff 核对）；③ 规则是否可被读成危险或不可逆动作；④ 新建的两个 agent 定义正文是否与 frontmatter 的 disallowedTools 矛盾。
约束：只读，不修改任何文件，不 commit。不做全库扫描，只看上述文件。
完成标准：给出 finding 列表，每条含 文件绝对路径:行号、置信 0-100（0 伪报，50 nit，75 很可能真会误导执行，100 确证）、证据、修改建议；低于 60 的不要列。若没有 ≥60 的问题，第一段明确写 clean，并列出你核对过的项目。
汇报格式：中文 markdown，≤ 50 行。
</task>
