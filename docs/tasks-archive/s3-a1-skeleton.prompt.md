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
目标：阶段 3 单元 A1 —— 建立 iOS 应用工程骨架：XcodeGen 的 project.yml 与生成的 .xcodeproj、SwiftUI 入口、依赖容器、TabView 导航、数据库生命周期接入、书架列表读库、打包脚本。
工作目录：/Users/wujie/Work/legado-ios/.claude/worktrees/ios（可写：App/（新目录）、tools/build-ipa.sh（新）、README.md 的「目录结构」段、Tests 不动；不得改 Packages/LegadoCore/Sources（若需要新增 public 入口，在报告里列出）；不 commit）
背景与入口：
- 计划 docs/2-阶段3-MVP界面/PLAN.md（架构、决策、单元划分）与 PROMPT.md；CLAUDE.md 项目速览。
- 已有包 Packages/LegadoCore（tools 6.1、语言模式 5、iOS 17 / macOS 14）：Storage/AppDatabase（内存 / 文件工厂，suspend() / resume()，见 docs/spec/storage-notes.md 的 App 层接入要求）、Storage/Repositories（BookshelfRepository 等）、Entities、Network/BoundedURLSessionHttpClient、WebBook、Import、Backup。
- 环境：Xcode 26.6、iOS 26.5 SDK、**没有 iOS 模拟器运行时**，构建用 -destination 'generic/platform=iOS'；XcodeGen 2.46.0 在 /opt/homebrew/bin/xcodegen；沙箱内写不了 ~/Library，xcodebuild 请加 -derivedDataPath .build/DerivedData 并设 CLANG_MODULE_CACHE_PATH 到工作区内。
产出：
1. App/project.yml：name Legado，bundle id com.legado.ios（占位），deploymentTarget iOS 17.0，SwiftUI 生命周期，targets：Legado（application，iPhone + iPad），LegadoTests（unit test bundle，host 为 Legado），本地包依赖 ../Packages/LegadoCore（product LegadoCore）；Info.plist 由 XcodeGen 生成（含 UILaunchScreen 空字典、支持方向）；不配置签名（CODE_SIGN_STYLE Manual、CODE_SIGNING_ALLOWED NO 由构建参数传）。运行 xcodegen 生成 App/Legado.xcodeproj 并一并提交生成物。
2. App/Sources/App/：LegadoApp.swift（@main，注入 AppContainer，监听 scenePhase 调用数据库 suspend / resume）、AppContainer.swift（数据库文件路径在 Application Support/Legado/legado.sqlite，BoundedURLSessionHttpClient，各 Repository，可用内存库构造供测试）、RootTabView.swift（书架 / 搜索 / 书源 / 设置四个 Tab，后三者先放占位视图）。
3. App/Sources/Features/Bookshelf/：BookshelfViewModel（@Observable，从 BookshelfRepository 读书列表，按分组过滤、按 durChapterTime 排序，空态）、BookshelfView（列表 / 网格切换，显示书名、作者、进度「已读 x / 共 y 章」、来源）。
4. App/Sources/Shared/：主题色与字体的最小 Theme、通用空态视图。
5. App/Tests/LegadoTests/BookshelfViewModelTests.swift：用内存库写入两本书验证排序与分组过滤（XCTest；若 host app 测试在无模拟器环境无法运行，则把 ViewModel 抽到不依赖 UIKit 的文件，并说明测试如何在 macOS 侧跑不了、留给有模拟器的机器；至少保证编译通过）。
6. tools/build-ipa.sh：xcodegen 生成 → xcodebuild archive（generic/platform=iOS，CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO）→ 从 .xcarchive 取 Products/Applications/Legado.app 打成 Payload/ 的未签名 Legado.ipa 到 dist/；脚本用 set -euo pipefail，中文注释按 ~/.claude/playbooks/shell.md（先读）。
7. README.md「目录结构」段填上 App/、Packages/、Tests/、tools/、docs/ 的实际用途。
约束：Swift 语言模式 5（App target 也用 5，避免严格并发返工）；不加第三方依赖；不 commit。
完成标准：在工作区执行 xcodegen（App 目录）与 CLANG_MODULE_CACHE_PATH=\"$PWD/.build/clang-cache\" xcodebuild -project App/Legado.xcodeproj -scheme Legado -destination 'generic/platform=iOS' -configuration Debug -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build，贴命令与末尾 15 行原始输出（沙箱内失败就贴完整错误，主会话代跑）；tools/build-ipa.sh 也尝试跑一次并报告结果；LegadoCore 全量 swift test 仍需通过。
汇报格式：中文 markdown ≤ 60 行：文件清单、构建输出、需要主会话代跑的项、需要 LegadoCore 新增入口的清单。
</task>
