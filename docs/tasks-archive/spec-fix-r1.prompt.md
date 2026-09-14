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
目标：按跨模型 review 给出的 6 条 finding 修正规则引擎规格文档 docs/spec/rule-engine.md，使其与 Kotlin 源码一致；只改这 6 处及其直接关联的示例，不重写其他段落。
工作目录：/Users/wujie/Work/legado-ios/.claude/worktrees/ios（只能修改 docs/spec/rule-engine.md；不 commit）
背景与入口：Kotlin 源码在主 checkout（只读）/Users/wujie/Work/legado-ios/app/src/main/java/io/legado/app/model/analyzeRule/ 与 AnalyzeUrlNetworkOptions.kt 同目录，commit cb664b84d（与规格标注的 6e08e1699 在这些文件上一致）。规格文档每条语义都要附 Kotlin 的 文件.kt:行号。
待修正 finding（每条先回源码核实，核实不成立就在报告里说明并不改）：
1. 规格第 204 行附近与第 344 行示例：元素列表的 %% 不会跳过空的首项。证据 AnalyzeByJSoup.kt:141、:169 无条件保存元素列表，:177 用第一个列表长度；字符串列表才在 :100 排除空结果。要求分开定义元素入口与字符串入口的 %% 语义，并修正示例（内容 <b>1</b> 的元素规则 tag.a%%tag.b 返回空列表）。
2. 规格第 49 行前缀识别表：兜底分支写成 Default 是错的。证据 AnalyzeRule.kt:626 创建 WebJs 段，:695 兜底只保留规则文本、不改模式。改为「保留传入模式」。
3. 规格第 149 行：空规则与剥离 CSS 前缀后为空混为一谈。证据 AnalyzeByJSoup.kt:72 原始空串立即返回空列表；只有非空规则处理后为空才在 :77 返回 [element.data()]。分别规定 getStringList("") 返回 []，getStringList("@CSS:") 才进入 data 分支，并调整 U3 描述。
4. 规格第 182 行新式索引零步长：AnalyzeByJSoup.kt:362 对 stepX=0 且 len>0 计算为 stepX+len 即 len，而非 1。len=4 时 tag.li[0:3:0] 只选索引 0。补零步长分支。
5. 规格第 322 行超时派生公式：AnalyzeUrlNetworkOptions.kt:78 翻倍超过上限钳制到 2147483647，:83 再应用 60000 下限。写成 max(60000, min(2147483647, 2×timeout))。
6. 规格第 248 行「空串继续向下找」：AnalyzeRule.kt:876 对本地绑定直接返回（含空串），:878、:882 书名章节名也直接返回；AnalyzeUrl.kt:436 对 extraParams 同样。限定空值过滤仅适用于后面的宿主变量查找链，并说明特殊键只在对应实体存在时才遮蔽。
约束：不改动其他段落的措辞与行号引用；改完后保持文档顶部 commit 标注不变；不改主 checkout。
完成标准：6 条逐条给出「已修 / 未修及原因」，每条附修改后的规格行号与对应 Kotlin 行号；跑 grep -c "\.kt:[0-9]" docs/spec/rule-engine.md 与 wc -l 贴结果。
汇报格式：中文 markdown ≤ 40 行。
</task>
