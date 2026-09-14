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
目标：做一个真实书源冒烟工具 tools/webbook-smoke（独立 SwiftPM 可执行包，依赖本地路径 ../../Packages/LegadoCore），主会话会用它对一个公开书源跑「搜索 → 详情 → 目录 → 正文」验证阶段 2 的完成判据。你不联网；只做工具与离线测试。
工作目录：/Users/wujie/Work/legado-ios/.claude/worktrees/ios（可写：tools/webbook-smoke/、Tests/LegadoCoreTests/ 新文件；不得改 Packages/LegadoCore/Sources 下任何文件（若发现缺少必要的 public 入口，在报告里列出，不要自己改）；不 commit）
背景与入口：已有 WebBook/{WebBook,BookList,BookInfo,BookChapterList,BookContent}.swift（async 入口，注入配置含 precisionSearch / tocCountWords / 缩进）、AnalyzeUrlExecutor、URLSessionHttpClient 与 BoundedURLSessionHttpClient、Import/SourceImporter（parseBookSources）、Entities/BookSource、Content/ContentProcessor。参考已有 tools/webdav-smoke 的包结构。
产出：
1. tools/webbook-smoke/Package.swift + Sources/WebBookSmoke/main.swift：命令行参数 --source <书源 JSON 文件路径> --keyword <搜索词> [--pick <第几条结果，默认 0>] [--chapters <正文抓取章数，默认 2>] [--timeout 秒]；流程：解析书源（多条则取第一条或按 --source-index）→ 搜索 → 打印前 5 条结果（书名 / 作者 / bookUrl 的 host 与路径长度，不打印完整 URL）→ 取第 pick 条跑详情 → 目录（打印章节数、前 3 与后 3 章标题）→ 前 N 章正文（打印每章字数与前 60 字）；每步打印耗时；任何一步失败打印错误 case 与该步上下文（不含 Cookie / Authorization）。退出码：全部成功 0，否则 1。
2. 输出里不得包含书源名称与站点域名以外的敏感信息；书源内容不写日志文件。
3. 用 ReplayHttpClient 对 main 的核心流程函数写一条离线测试（把流程封装成可注入 HttpClient 的函数，main 只做参数解析），走 Tests/Conformance/fixtures/webbook 的自造站点。
4. tools/webbook-smoke/README.md（中文 ≤ 25 行）：用法与限制。
完成标准：swift build --package-path tools/webbook-smoke 成功；工作区全量 swift test 通过；报告附命令与末尾 10 行、测试总数、若需要 LegadoCore 增加 public 入口的清单。
汇报格式：中文 markdown ≤ 40 行。
</task>
