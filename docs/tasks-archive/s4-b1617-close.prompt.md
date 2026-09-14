# 任务：B16 / B17 收口——合并态全量测试

## 目标
B16（备用图标）与 B17（WebSocket，返修完毕）尚未一起验证。在合并态跑 tools/appcore-check 全量与 tools/icon-render 的 check.sh，回报真实数字（LegadoCore 全量 539 已由 B17 r2 刚跑过，不必重跑）。失败只允许修测试间干扰（端口占用、共享目录、顺序），业务失败原样报告。

## 范围
- 允许改：测试间干扰的修复。不动其他文件；不运行 xcodegen / xcodebuild；不 commit；不在 /tmp 做副本；不联网；不新建 docs；不对真实 WebDAV 发请求。

## 已知上下文
- worktree：`/Users/wujie/Work/legado-ios/.claude/worktrees/ios`。磁盘只剩约 1.5 GB，不留大日志。
- 命令（先 `mkdir -p .build/tmp`）：
  ```sh
  CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/clang-cache" TMPDIR="$PWD/.build/tmp" swift test --package-path tools/appcore-check --cache-path "$PWD/.build/cache" --disable-sandbox --disable-automatic-resolution --skip-update
  bash tools/icon-render/check.sh
  ```

## 交付格式（≤ 20 行）
两条命令的「Executed N tests, with M failures」原文各一行；修了什么；未解决项。
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
