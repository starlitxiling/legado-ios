# 任务：阶段 4 批次 2 收口——背景音频配置 + 合并态全量测试

## 目标
批次 2（B4 WebView / B5 纯 JS 书源 / B6 听书 / B7 MOBI-PDF）四个单元已各自返修完毕但尚未一起验证。你要：① 在 `App/project.yml` 的 Legado target 的 info properties 里加 `UIBackgroundModes: [audio]`（听书后台播放必需；对齐 Android `service/BaseReadAloudService` 的前台服务语义）；② 在合并态跑 LegadoCore 与 tools/appcore-check 两套全量测试并回报真实数字。

## 范围
- 允许改：`App/project.yml`（只加这一个键；若 `info.properties` 已有 `UIBackgroundModes`，合并而不是覆盖）。
- 若全量测试有失败：只允许修 **测试之间的相互干扰**（临时目录冲突、共享单例状态、顺序依赖），并写明改了什么、为什么；**业务逻辑失败不许改，原样报告**。
- 不动其他任何文件；不运行 xcodegen / xcodebuild（主会话代跑）；不 commit；不在 /tmp 做隔离副本；不联网。

## 已知上下文
- worktree：`/Users/wujie/Work/legado-ios/.claude/worktrees/ios`（orphan 分支 ios）。`App/project.yml` 是 XcodeGen 真源，生成物 `App/Legado.xcodeproj` 由主会话重新生成。
- 四单元最近各自报告：LegadoCore 全量 388 项通过（B6 最后跑），appcore-check 未在合并态全量跑过。
- 测试命令（必须原样带这些环境变量与参数）：
  ```sh
  CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/clang-cache" TMPDIR="$PWD/.build/tmp" swift test --package-path Packages/LegadoCore --cache-path "$PWD/.build/cache" --disable-sandbox --disable-automatic-resolution --skip-update
  CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/clang-cache" TMPDIR="$PWD/.build/tmp" swift test --package-path tools/appcore-check --cache-path "$PWD/.build/cache" --disable-sandbox --disable-automatic-resolution --skip-update
  ```
  `mkdir -p .build/tmp` 后再跑。

## 交付格式（≤ 40 行）
1. 结论先行：两套全量的「Executed N tests, with M failures」原文各一行。
2. project.yml 的 diff（几行）。
3. 若修了测试干扰：文件:行号 + 一句原因。
4. 未解决项。
不要回贴日志全文。
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
