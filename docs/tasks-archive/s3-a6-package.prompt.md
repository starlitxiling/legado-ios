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
目标：阶段 3 单元 A6 —— 持续集成与安装说明：GitHub Actions 工作流（构建未签名 ipa + 跑离线测试）、README 的自签安装步骤、打包脚本的健壮性收尾。
工作目录：/Users/wujie/Work/legado-ios/.claude/worktrees/ios（可写：.github/workflows/ios.yml（新）、tools/build-ipa.sh（已有，可改）、README.md、docs/spec/ 下新增 release-notes.md 若需要；不改 App/Sources、Packages/LegadoCore/Sources；不 commit；不联网）
背景与入口：tools/build-ipa.sh（A1 写的：xcodegen → xcodebuild archive generic/platform=iOS 无签名 → Payload 打包 ipa 到 dist/），App/project.yml，tools/appcore-check、Packages/LegadoCore 的测试命令（见 docs/2-阶段3-MVP界面/PROGRESS.md 与各任务用的 CLANG_MODULE_CACHE_PATH / --cache-path 参数），仓库已有 .github/labels.yml 与 issue 模板。分发决策：自签侧载（AltStore / Sideloadly），不做 TestFlight / App Store；PLAN §7。本机没有 GitHub Actions 运行环境，你只能静态编写并用 bash -n / actionlint（若本机有）校验。
产出：
1. .github/workflows/ios.yml：触发 push 到 ios 分支与 PR；runner macos-15（或最新 macOS 镜像，写明 Xcode 版本选择 xcode-select）；步骤：checkout → brew install xcodegen → swift test（LegadoCore、appcore-check）→ tools/build-ipa.sh → upload-artifact dist/*.ipa；缓存 SwiftPM 依赖（actions/cache 键含 Package.resolved 哈希）；失败必须让 job 失败（脚本非零退出透传）。
2. tools/build-ipa.sh 收尾：支持 CONFIGURATION（默认 Release）、输出文件名带版本号与 git 短 hash、失败时清理暂存目录、打印产物路径与大小；中文注释按 ~/.claude/playbooks/shell.md（先读）。
3. README.md：「安装」段（自签侧载：AltStore 与 Sideloadly 两条路径、免费账号 7 天续签与 3 应用上限、从 Releases / Actions artifact 取 ipa）、「构建」段（本机前置：Xcode 与 iOS 平台组件、xcodegen；命令：tools/build-ipa.sh）、「功能范围与已知限制」段（链接 docs/spec 的四份兼容文档与阶段 SUMMARY）。
4. 校验：bash -n tools/build-ipa.sh；用 python3 -c 'import yaml' 若可用则解析 ios.yml，否则说明未校验 YAML。
完成标准：贴校验命令与输出；列出文件清单。
汇报格式：中文 markdown ≤ 35 行。
</task>
