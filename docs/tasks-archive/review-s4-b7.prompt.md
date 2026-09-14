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
目标：独立复审阶段 4 单元 B7（MOBI / AZW3 解析移植与 PDF 分章）。
工作目录：/Users/wujie/Work/legado-ios/.claude/worktrees/ios（分支 ios）
背景与入口：新增 Packages/LegadoCore/Sources/LegadoCore/LocalBook/Mobi/{PdbReader,MobiHeader,PalmDocDecoder,HuffCdicDecoder,MobiBook}.swift、LocalBook/MobiFile.swift、LocalBook/PdfFile.swift、LocalBook.swift:25 分派；App 端 LocalImport 扩展名；测试 MobiPdfTests、MobiBinaryTests 等。Kotlin 只读（commit cb664b84d）：/Users/wujie/Work/legado-ios/app/src/main/java/io/legado/app/lib/mobi/*（34 个文件：PDB 头 / 记录表、MOBI 头字段与 EXTH、PalmDoc LZ77、HUFF / CDIC、KF7 / KF8 判定与 boundary、INDX / NCX / guide、骨架 SKEL / FDST 片段重建、图片记录索引、编码）、model/localBook/MobiFile.kt（目录 / 正文 / 封面抽取与 HTML 处理）、model/localBook/PdfFile.kt（分章策略）。
审查角度：① 逐文件对照 Kotlin：PDB 记录偏移越界防护、MOBI 头版本差异（v6 / v8）、EXTH 记录类型（100 作者、503 标题、封面 201 / 202 等）、PalmDoc 尾随字节（trailing entries / multibyte）处理、HUFF / CDIC 的表解析与递归深度、KF8 boundary 定位与 FDST / SKEL / FRAG 重建、NCX 目录层级与 filepos 到章节的映射、编码 cp1252 / UTF-8 判定；② 目录与正文抽取：章节切分依据（NCX 还是 HTML 内的 <mbp:pagebreak> / filepos 锚点）与 Kotlin 一致、正文 HTML → 文本的处理是否复用 EPUB 路径；③ PDF：默认分章策略与 Kotlin PdfFile 是否一致（每页一章？还是固定页数），文本提取的换行与空白；④ 内存与大文件（整文件读入 vs 按记录读取）；⑤ 测试样本为自造，HUFF / CDIC 与 KF8 是否被真实样本覆盖，报告里是否如实标注未覆盖；⑥ 测试是否迁就实现。
约束：只读，不修改文件，不 commit，不编译。
完成标准：finding 列表（文件绝对路径:行号、置信 0-100、问题与建议），< 60 不列；没有就写 clean。
汇报格式：中文 markdown ≤ 50 行。
</task>
