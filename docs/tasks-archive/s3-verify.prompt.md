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
目标：阶段 3 五个单元（A1 骨架、A2 书源管理、A3 搜索详情目录、A4 阅读器、A5 设置备份）合并后的验证：重新生成 Xcode 工程、跑全部离线测试，并给出合并态统计。只跑不改（xcodegen 生成物除外）。
工作目录：/Users/wujie/Work/legado-ios/.claude/worktrees/ios
做法：① 在 App/ 下执行 /opt/homebrew/bin/xcodegen 重新生成 Legado.xcodeproj（让新增的 Features 目录进入工程），报告生成的 target 与源文件计数；② 在 Packages/LegadoCore 用 CLANG_MODULE_CACHE_PATH=\"$PWD/.build/clang-cache\" swift test --cache-path .build/cache --config-path .build/config --security-path .build/security --disable-sandbox 跑全量；③ 在 tools/appcore-check 用同样参数跑全量（含 AppCoreCheckTests、SettingsBackupCheckTests、ReaderCheckTests、DatabaseLifecycleCoordinator 等全部目标）；④ tools/webbook-smoke 与 tools/webdav-smoke 各 swift build 一次确认仍可编译；⑤ 汇总：各包测试总数与失败数、失败用例 id 与原始错误（若有）。不要 xcodebuild（本机 iOS 平台组件仍在下载，主会话代跑）。
约束：除 xcodegen 生成物外不修改任何文件，不 commit，不联网。
完成标准：贴每条命令、退出码与末尾 10 行原始输出；有失败就完整列出。
汇报格式：中文 markdown ≤ 45 行。
</task>
