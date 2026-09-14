# 任务：阶段 4 批次 3 收口——后台刷新配置 + 合并态全量测试

## 目标
批次 3（B8 书源编辑进阶 / B9 阅读器进阶 / B10 书架进阶与下载）三个单元已各自返修完毕但尚未一起验证。你要：① 在 `App/project.yml` 的 Legado target `info.properties` 里加 `BGTaskSchedulerPermittedIdentifiers: [io.legado.ios.refresh]`，并把已有 `UIBackgroundModes: [audio]` 改为 `[audio, fetch]`（保留 audio）；② 在合并态跑 LegadoCore 与 tools/appcore-check 两套全量测试并回报真实数字；③ 若 `ReadAloudTests.testHttpRuleAndCache` 失败（此前某次全量报 `unmatched(method: "GET", url: https://tts.test/hello/5)`，其它两次全量通过），诊断是测试间干扰（共享缓存目录 / 单例状态 / 顺序依赖）还是业务逻辑，只允许修前者并说明；业务逻辑失败原样报告。

## 范围
- 允许改：`App/project.yml`（只改上述两键）；测试间干扰的修复（写明改了什么、为什么）。
- 不动其他任何文件；不运行 xcodegen / xcodebuild（主会话代跑）；不 commit；不在 /tmp 做隔离副本；不联网；不新建 docs 文档。

## 已知上下文
- worktree：`/Users/wujie/Work/legado-ios/.claude/worktrees/ios`（orphan 分支 ios）。`App/project.yml` 是 XcodeGen 真源。
- 最近各自报告：B10 全量 LegadoCore 411、appcore-check 157 通过；B8 全量 Core 408 中 1 失败（上述 TTS 用例）。
- 测试命令（原样带环境变量与参数，先 `mkdir -p .build/tmp`）：
  ```sh
  CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/clang-cache" TMPDIR="$PWD/.build/tmp" swift test --package-path Packages/LegadoCore --cache-path "$PWD/.build/cache" --disable-sandbox --disable-automatic-resolution --skip-update
  CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/clang-cache" TMPDIR="$PWD/.build/tmp" swift test --package-path tools/appcore-check --cache-path "$PWD/.build/cache" --disable-sandbox --disable-automatic-resolution --skip-update
  ```
- 全量跑两遍 LegadoCore（第二遍加 `--filter ReadAloudTests` 单跑）以判断上述用例是否稳定。

## 交付格式（≤ 40 行）
1. 结论先行：两套全量的「Executed N tests, with M failures」原文各一行；ReadAloudTests 单跑结果一行。
2. project.yml 的 diff（几行）。
3. 若修了测试干扰：文件:行号 + 一句原因。
4. 未解决项。不要回贴日志全文。
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
