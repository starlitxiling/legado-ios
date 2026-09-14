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
目标：独立复审阶段 4 单元 B1（发现分类解析、发现页、封面 / 正文图片下载与解密、封面视图、阅读器正文图片）。
工作目录：/Users/wujie/Work/legado-ios/.claude/worktrees/ios（分支 ios）
背景与入口：新增 Packages/LegadoCore/Sources/LegadoCore/Explore/ExploreKinds.swift、Images/ImageDownloader.swift、WebBook 的 explore 入口改动、App/Sources/Features/Explore/*、Shared/{RemoteImage,RemoteImageViewModel}.swift、Reader 的 Paginator / ReaderLayout 图片改动、BookshelfView / SearchView 的封面接入；测试 Packages/LegadoCore/Tests/LegadoCoreTests/Explo*、tools/appcore-check 的 ExploreImagesTests。Kotlin 只读（commit 2bdd3c58b）：/Users/wujie/Work/legado-ios/app/src/main/java/io/legado/app/data/entities/BookSource.kt（exploreKinds 解析：换行 / && / :: / JSON / 分组标题 / <js> 动态、缓存）、model/webBook/BookList.kt explore 分支、help/book/BookHelp.kt（saveImage / getImage 的目录、命名、header / cookie）、model/ImageProvider.kt、utils/ImageUtils.kt（imageDecode 的 JS 绑定与返回字节）、ui/book/explore。
审查角度：① exploreKinds 各形态解析边界（空、注释行、::url 缺失、JSON 数组与对象、分组标题以 「标题::」判定、动态 JS 返回值形态）与 Kotlin 一致；② 发现分页 {{page}} 与 exploreScreen、结果去重与 SearchBook 字段；③ 图片下载：请求头（Referer / UA / 书源 header）、cookie、缓存目录与命名、imageDecode 绑定（src / result 字节）与返回类型、失败回退；④ RemoteImage 的取消与复用、主线程；⑤ 阅读器图片独页对字符偏移与进度的影响（图片占位是否算进 durChapterPos 坐标，与 Android 的 <img> 处理一致性）；⑥ 测试是否迁就实现。
约束：只读，不修改文件，不 commit，不编译。
完成标准：finding 列表（文件绝对路径:行号、置信 0-100、问题与建议），< 60 不列；没有就写 clean。
汇报格式：中文 markdown ≤ 45 行。
</task>
