# 任务：阶段 4 批次 4 收口 2——备用图标配置 + 合并态 appcore-check 全量

## 目标
① B13b 实现了 launcherIcon 切换（App/Sources/Features/Settings/LauncherIconSettingsView.swift，键值 launcher1…launcher6，要求见 docs/spec/settings-compat.md:62 附近）。你要把 Android 仓库自身的 6 套启动图标（/Users/wujie/Work/legado-ios/app/src/main/res/mipmap-xxxhdpi/ 下 ic_launcher*.png 及 res/values/array_values.xml:4 的 launcher 名称映射；只读 Kotlin 侧，commit cb664b84d）复制到 App/Resources/AlternateIcons/<name>@2x.png 与 @3x.png（用 sips 缩放到 120×120 与 180×180；主图标不动），并在 `App/project.yml` 的 Legado target 加 `CFBundleIcons` / `CFBundleIcons~ipad` 的 `CFBundleAlternateIcons`（launcher1…launcher6 各 `CFBundleIconFiles`），XcodeGen 需把该目录作为资源收进 target（按 project.yml 现有 sources / resources 写法追加，不改其他键）。② B13b r3 之后 appcore-check 全量未在合并态跑过：跑一遍并回报真实数字；失败按「只修测试间干扰」处理，业务失败原样报告。

## 范围
- 允许改：`App/project.yml`（只加上述键与资源目录）、新增 `App/Resources/AlternateIcons/`、测试干扰修复。
- 不动其他任何文件；不运行 xcodegen / xcodebuild（主会话代跑）；不 commit；不在 /tmp 做副本；不联网；不新建 docs。

## 已知上下文
- worktree：`/Users/wujie/Work/legado-ios/.claude/worktrees/ios`。磁盘只剩约 1.8 GB，不留大日志。
- 测试命令（先 `mkdir -p .build/tmp`）：
  ```sh
  CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/clang-cache" TMPDIR="$PWD/.build/tmp" swift test --package-path tools/appcore-check --cache-path "$PWD/.build/cache" --disable-sandbox --disable-automatic-resolution --skip-update
  ```

## 交付格式（≤ 30 行）
1. 结论先行：appcore-check「Executed N tests, with M failures」原文一行。
2. project.yml 的 diff（几行）与图标文件清单（名称 + 尺寸）。
3. 若修了测试干扰：文件:行号 + 一句原因。
4. 未解决项。
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
