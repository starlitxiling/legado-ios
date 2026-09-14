# 任务：阶段 4 批次 4 收口——合并态全量测试

## 目标
批次 4（B11 RSS / B12 漫画音频 / B13 备份 / B13b 设置全集 / B14 Web 服务 / B15 实体补齐）六个单元已各自返修完毕。你要在合并态跑 LegadoCore 与 tools/appcore-check 两套全量测试并回报真实数字；若有失败，判断是测试间干扰（共享目录 / 单例 / 顺序 / 端口占用）还是业务逻辑：只允许修前者并说明，业务逻辑失败原样报告（文件:行号 + 失败原文）。

## 范围
- 允许改：测试间干扰的修复（写明改了什么、为什么）。
- 不动其他任何文件；不运行 xcodegen / xcodebuild；不 commit；不在 /tmp 做隔离副本；不联网；不新建 docs；不得对真实 WebDAV 发请求。

## 已知上下文
- worktree：`/Users/wujie/Work/legado-ios/.claude/worktrees/ios`。最近各自报告：B13b 后 LegadoCore 全量 513 通过；appcore-check 全量未在合并态跑过（各单元只跑了 filter），此前某次曾出现 BackupReviewFixTests 的 `Fulfilled inverted expectation "恢复应等待自动备份"` 与 signal 11，可能是当时半成品；也曾有 WebService 测试用固定端口。
- 测试命令（原样带环境变量与参数，先 `mkdir -p .build/tmp`）：
  ```sh
  CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/clang-cache" TMPDIR="$PWD/.build/tmp" swift test --package-path Packages/LegadoCore --cache-path "$PWD/.build/cache" --disable-sandbox --disable-automatic-resolution --skip-update
  CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/clang-cache" TMPDIR="$PWD/.build/tmp" swift test --package-path tools/appcore-check --cache-path "$PWD/.build/cache" --disable-sandbox --disable-automatic-resolution --skip-update
  ```
- appcore-check 全量跑两遍以判断稳定性；有 signal 崩溃时用 `--filter` 二分定位崩溃用例。

## 交付格式（≤ 40 行）
1. 结论先行：两套全量的「Executed N tests, with M failures」原文各一行（appcore-check 两遍各一行）。
2. 若修了测试干扰：文件:行号 + 一句原因。
3. 业务逻辑失败清单（若有）。
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
