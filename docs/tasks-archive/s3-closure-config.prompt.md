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
目标：阶段 3 收口的两处配置修正。
工作目录：/Users/wujie/Work/legado-ios/.claude/worktrees/ios（只改 .gitignore 与 Packages/LegadoCore/Package.swift；不 commit；不联网）
1. 根 .gitignore 增加 dist/（tools/build-ipa.sh 的 ipa 输出目录），并确认 git check-ignore -q dist 通过。
2. Packages/LegadoCore/Package.swift：消除 SwiftPM 警告「found 2 file(s) which are unhandled」——Sources/LegadoCore/Resources/public_suffix_list.dat 与 PUBLIC_SUFFIX_LIST_LICENSE.md 不是运行时资源（PSL 已转成静态 Swift 表），用 exclude: [\"Resources\"] 排除；不要改成 resources:（会改变 bundle 结构）。改后在 Packages/LegadoCore 用 CLANG_MODULE_CACHE_PATH=\"$PWD/.build/clang-cache\" swift build --cache-path .build/cache --config-path .build/config --security-path .build/security --disable-sandbox 确认无该警告、编译通过；再跑一次全量 swift test 确认 276 项仍通过。
完成标准：贴命令与末尾 8 行输出、警告计数。
汇报格式：中文 markdown ≤ 20 行。
</task>
