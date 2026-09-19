<subagent_contract>
你是一个子代理。你的最后一条消息是唯一交付物，调用方看不到其他任何内容。必须遵守：
1. 所有发现、结论、文件路径都写进最后一条消息；禁止以计划、提问或"接下来我会…"收尾——先做完，再汇报。
2. 第一段先给结论（发生了什么/发现了什么），细节放后面。
3. 涉及代码的每条论断都带 `文件绝对路径:行号` 引用。
4. 如实汇报：失败就原样贴失败输出；跳过的步骤要说明；没验证过的事不得声称完成；不确定就标注"未验证"。
5. 只做指派的任务：不扩 scope、不顺手重构、不 commit/push。
6. 改代码时贴合周边代码风格；注释只写代码本身无法表达的约束，不写解释本次改动的注释。
7. 用完整句子；禁止碎片化短语、箭头链（A→B）、自造缩写和代号、表情符号。
8. 被卡住就停下，精确说明缺什么信息；不许猜测、不许编造。
9. 关键假设失效（任务书写的与代码实际不符）立即停机汇报，不要硬做。
</subagent_contract>

<task>
目标：轮次 4 单元 C6 —— 给已有的一致性用例运行器套一个**可执行外壳**，让本机在没有 Xcode（因而没有 XCTest）的情况下，
也能跑完整的规则引擎一致性语料并得到通过率。这是后续所有规则引擎修改的唯一验证手段，优先级最高、范围要小。

工作目录：/Users/xiling/Work/legado-ios/.claude/worktrees/ios

## 本机环境的硬约束（很重要）

本机**只有 Command Line Tools，没有 Xcode**，`XCTest` 模块不存在。
`swift test` 在本仓库任何包上都会报 `unable to resolve module dependency: 'XCTest'`。
**不要试图跑 `swift test`，也不要因为跑不了测试就停工。** `swift build` 与 `swift run` 可用。
依赖已 resolve 完毕，命令加 `--disable-automatic-resolution --skip-update` 避免联网（沙箱无网络）。

命令前缀（在工作目录下执行）：
```
CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/clang-cache" TMPDIR="$PWD/.build/tmp" \
  swift build --package-path <包路径> --cache-path "$PWD/.build/cache" --config-path "$PWD/.build/config" --security-path "$PWD/.build/security" --disable-sandbox
```

## 已知现状（主会话已核实）

- 运行器本体已存在于**库目标**中（不是测试目标）：
  `Packages/LegadoCore/Sources/LegadoCore/Conformance/ConformanceRunner.swift` 与 `ConformanceCase.swift`。
- 语料在 `Packages/LegadoCore/Tests/Conformance/fixtures/` 下，至少有 `golden/` 与 `synthetic/` 两个子目录，
  另有 `webbook/source.json`。历史记录称一致性用例共 142 条且曾全部通过。
- 已有四个可执行 SwiftPM 包可作写法参照：`tools/webdav-smoke`、`tools/webbook-smoke`、`tools/icon-render`、`tools/backup-import-check`。
  其中 `tools/backup-import-check` 是另一个子代理正在**同时创建**的，**不要修改它**，只可参照其 `Package.swift` 的依赖写法。

## 产出

1. **新可执行包 `tools/conformance-run`**：
   - 通过相对路径依赖 `Packages/LegadoCore`，复用库里已有的 `ConformanceRunner`，**不要重新实现一套求值逻辑**。
   - 默认扫描 `Packages/LegadoCore/Tests/Conformance/fixtures/` 下的全部语料文件；可选接受一个或多个路径参数来只跑指定文件或目录。
   - 输出：每个语料文件的「通过数 / 总数」，全局汇总的「通过数 / 总数 / 通过率」，以及**每条失败用例的用例标识、期望值与实际值**
     （失败详情是本工具存在的意义，务必打印足够定位的信息，但单条输出控制在合理长度，不要刷屏）。
   - 有失败时退出码非零，全通过时为零。
   - `tools/conformance-run/.gitignore` 忽略 `.build/`。
2. 如果为了让库外调用得通，必须给 `ConformanceRunner` / `ConformanceCase` 加 `public` 或补一两个入口方法，
   **允许最小改动**，但不得改变既有求值行为与用例语义。改了什么要在报告里逐条列出。

## 范围与约束

- 可写：`tools/conformance-run/`（新建）；必要时 `Packages/LegadoCore/Sources/LegadoCore/Conformance/` 的**可见性最小改动**。
- 不要动：`Packages/LegadoCore` 下 Conformance 以外的源码、`Tests/` 下的语料文件（**一条用例都不许改**）、
  `App/`、其他 `tools/` 子包、`docs/4-*`、`.env.local`。
- 不加第三方依赖。不 commit、不 push。
- **绝对不许为了让通过率好看而修改语料或放宽断言**。当前语料的真实通过率是什么就报什么；
  如果跑出来不是 142/142，那本身就是一个重要发现，如实报告并给出每条失败的详情。

## 完成标准

1. `swift build` 在 `tools/conformance-run` 上通过。
2. `swift run --package-path tools/conformance-run ...` 能跑完全部语料并打印汇总。
3. 报告里给出：语料文件数、用例总数、通过数、通过率，以及失败用例的完整清单（若有）。
4. 报告附该命令的原始输出末尾 25 行。

## 汇报格式

中文 markdown ≤ 45 行：结论先行（通过率数字放第一句） / 新包文件清单与 `文件:行号` /
对 Conformance 源码所做的可见性改动逐条 / 工具用法一行 / 原始输出末尾 25 行 / 未验证项。
