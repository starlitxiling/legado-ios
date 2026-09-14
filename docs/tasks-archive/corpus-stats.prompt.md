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
目标：对已下载到本机的公开 Legado 书源合集做静态频率统计，产出「JS 宿主 API 实现优先级表」，决定 iOS 端 JavaScriptCore 宿主层先实现什么。
工作目录：/Users/wujie/Work/legado-ios/.claude/worktrees/ios（只能写入 tools/corpus/ 与 docs/0-iOS适配规划/宿主API优先级.md，目录不存在就创建；不 commit）
背景与入口：
- 合集缓存目录（只读，仓库外）：/private/tmp/claude-501/-Users-wujie-Work-legado-ios/d9bfa378-d458-442c-bd30-3507bcb06aea/scratchpad/corpus/，内有 8 个 JSON 文件（每个是书源对象数组，合计约 9700 条，按 bookSourceUrl 去重约 4097 个）与 manifest.tsv（列：文件名、GitHub 仓库、仓库内路径、commit sha、下载时间 UTC、字节数）。
- Android 端暴露给书源 JS 的宿主对象 java 的方法清单来自主 checkout（只读）：/Users/wujie/Work/legado-ios/app/src/main/java/io/legado/app/help/JsExtensions.kt 与 JsEncodeUtils.kt，用 grep -n "fun " 提取全部方法名作为统计词表（约 103 个唯一名）。
- 注入变量：java cookie cache source book result baseUrl chapter chapters title src nextChapterUrl page key speakText speakSpeed infoMap。
- 需重点关注的 Rhino 特有特性：E4X（XML 字面量、.@attr、.. 运算）、Packages.、importClass / importPackage、new java.lang.* 或 java.util.*、把返回值当 Java 字符串用的 .length() 写法、String(...) 包装、CryptoJS.、let / const 使用。
- 书源 JSON 结构：顶层 bookSourceUrl、bookSourceName、jsLib、loginUrl、loginCheckJs、header、searchUrl、exploreUrl，以及 ruleSearch / ruleExplore / ruleBookInfo / ruleToc / ruleContent 各自的规则字段（值为字符串或对象）。JS 出现在 <js>…</js>、@js:、{{ }}、jsLib、loginCheckJs、以及 URL 的 ,{...} 选项里的 js / webJs / bodyJs。
- 写 Python 前必须先读 /Users/wujie/.claude/playbooks/python.md 并遵守；脚本只用标准库；python3 已安装。
产出：
1. tools/corpus/analyze_sources.py：输入合集目录路径（命令行参数），按 bookSourceUrl 去重后输出 markdown 统计表：① 规则模式使用率（@css: / @XPath: 或 / 开头 / @json: 或 $. / <js> / @js: / @webjs: / {{ }} / ## / && / || / %% / @get / @put），按「使用该特性的书源数 / 去重总数」计；② java.<method>( 每个方法的书源数，降序，含累计覆盖率（覆盖率定义：至少用到一个 java 方法的书源里，只实现前 N 个方法就能完全满足的书源占比）；③ Rhino 特有特性各自的书源数，各给 2 个脱敏示例片段（只保留 JS 片段，去掉 URL 与站名）；④ URL 选项键（method charset headers body webView js retry type webJs bodyJs timeout followRedirects dnsIp 等）各自的书源数；⑤ 注入变量使用数。统计口径写进脚本 docstring 与 tools/corpus/README.md。
2. docs/0-iOS适配规划/宿主API优先级.md：顶部写语料来源表（取 manifest.tsv 的仓库、路径、sha、下载时间，不写站名）与统计日期；正文放上面各表；末尾给分级建议：一级 = 达到 80% 覆盖率所需的最小方法集合；二级 = 再到 95%；三级 = 其余；并单列「Rhino 特有语义的实际使用率」小节，明确回答 E4X / Packages. / .length() 三项是否可以不支持。
约束：只做静态文本分析，不执行任何书源 JS，不发起任何网络请求。仓库内不得出现书源 URL、站名、完整书源；示例片段要脱敏。合集文件很大，用脚本处理，不要整读。
完成标准：脚本用 python3 -m py_compile 通过；实际跑一次生成上述 md；报告里附命令与输出前 30 行；给出语料总数与去重数、一级 / 二级方法数与覆盖率、E4X / Packages / .length() 使用率。
汇报格式：中文 markdown ≤ 60 行：语料来源表；关键数字；验证输出；未解决项与分级建议一句话结论。不要把完整表格贴回来。
</task>
