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
9. 关键假设失效（任务书写的规格与 Kotlin 实际不符）立即停机汇报，不要按任务书硬做。
</subagent_contract>

<task>
目标：轮次 4 单元 C1b —— 用真实 Legado 备份包驱动，修复 iOS 备份导入器对 `highlightRule.json` 与 `servers.json` 两个条目的解析失败；并顺带建立一个不依赖 XCTest 的本地导入校验工具，供本机在 Xcode 缺失期间做验证。

工作目录：/Users/xiling/Work/legado-ios/.claude/worktrees/ios

## 背景（已由主会话实测，不要推翻）

用人类提供的坚果云 WebDAV 账号跑 `tools/webdav-smoke`（只读 PROPFIND + GET），成功下载并导入了一个**真实备份包**，导入报告为：
- 成功：books 82、book_sources 4198、replace_rules 20、readRecord 138、bookmarks 154、book_groups 9
- 跳过文件：`homepage.json`、`readRecordDetail.json`、`webSearchEngines.json`
- **失败文件：`highlightRule.json`、`servers.json`** ← 本单元要修的就是这两个

该备份包已保存到 `/Users/xiling/Work/legado-ios/.claude/worktrees/ios/.build/fixtures-local/real-backup.zip`（2.0 MB，23 个条目，gitignored，**不要提交它，也不要把它复制进仓库受版本控制的目录**）。

两个失败条目的真实内容（主会话已解压查看）：
- `highlightRule.json`（96 字节）是一个 **JSON 对象**而非数组：`{"a": [], "b": ["默认分组"], "c": "", "d": true, "e": true, "f": true}`
- `servers.json`（24 字节）根本不是 JSON：`bF6sxj5FCEbxFyh1WJYCrQ==`（看起来是 base64 或加密串）

## 本机环境的硬约束（很重要）

本机**只有 Command Line Tools，没有 Xcode**，因此 **`XCTest` 模块不存在**，`swift test` 在本仓库任何包上都会失败并报
`unable to resolve module dependency: 'XCTest'`。**不要试图跑 `swift test`，也不要因为跑不了测试就停工。**
`swift build` 与 `swift run` 是可用的（库目标编译正常）。依赖已 resolve 完毕，跑命令时加 `--disable-automatic-resolution --skip-update` 避免联网（沙箱无网络）。

统一的命令前缀（在工作目录下执行）：
```
CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/clang-cache" TMPDIR="$PWD/.build/tmp" \
  swift build --package-path <包路径> --cache-path "$PWD/.build/cache" --config-path "$PWD/.build/config" --security-path "$PWD/.build/security" --disable-sandbox
```

## Kotlin 规格真源（只读）

路径前缀 `/Users/xiling/Work/legado-ios/app/src/main/java/io/legado/app/`（master 工作树，Kotlin 自 commit 2bdd3c58b 起未变动）。
**一律以 Kotlin 为准，不要凭印象推断 Legado 的行为。** 主会话上面给的「对象而非数组」只是观察到的现象，
这两个文件在 Android 端到底是什么语义、由谁写出、恢复时怎么读，必须你自己去 Kotlin 里查实。建议入口：
- `help/storage/Backup.kt`（备份写出：哪些文件、各自的序列化来源）
- `help/storage/Restore.kt` 或同目录的恢复实现（恢复读入：每个文件的目标类型与失败处理）
- 搜索 `highlightRule`、`servers`、`HighlightRule`、`Server` 等标识符定位实体与 DAO

注意 `servers.json` 的内容形态提示它可能不是普通实体列表，先查清它在 Android 端是什么，再决定 iOS 该怎么处理。

## iOS 侧现状入口（只读定位用）

- `Packages/LegadoCore/Sources/LegadoCore/Backup/BackupImporter.swift`（导入主流程、`report.failures` 的填充点）
- 同目录 `BackupFileManifest.swift`、`BackupSelection.swift`、`BackupArchive.swift`
- `Packages/LegadoCore/Sources/LegadoCore/Entities/`（实体定义）
- `docs/spec/backup-notes.md`、`docs/spec/entities-compat.md`（既有差异记录，需按本次结论更新）

## 产出

1. **新工具 `tools/backup-import-check`**：一个 SwiftPM 可执行包（参照 `tools/webdav-smoke/Package.swift` 的写法，
   通过相对路径依赖 `Packages/LegadoCore`），接受一个本地 zip 路径参数，跑 `BackupImporter` 的完整导入，
   打印各表条目数、跳过文件、失败文件及**每个失败文件的具体错误原因**（现有 smoke 只打印文件名，不够用），
   有失败时退出码非零。它不依赖网络、不依赖 XCTest，是本机当前唯一可用的端到端验证手段。
   在 `tools/backup-import-check/.gitignore` 里忽略 `.build/`。
2. **修复 `highlightRule.json` 的导入**：按 Kotlin 实际语义处理该条目。
3. **修复 `servers.json` 的导入**：按 Kotlin 实际语义处理该条目。若查实 Android 端本身就不把它当普通实体恢复
   （例如它是加密串、或属于某类不参与恢复的内容），那么正确的行为可能是「跳过」而不是「解析」——
   以 Kotlin 为准，并把结论写进文档，不要为了让它变绿而编造解析逻辑。
4. **更新 `docs/spec/backup-notes.md`**：补充这两个条目的行为、与 Android 的一致性结论、仍不支持的部分。中文，增量不超过 25 行。
5. **补单元测试**（写进 `Packages/LegadoCore/Tests/LegadoCoreTests/` 既有备份测试文件的风格里），覆盖这两个条目的解析分支。
   **本机跑不了这些测试**（无 XCTest），这是已知情况：请照常写好测试代码并确保它们在语法与 API 上正确，
   在报告里明确标注「测试已写但本机未执行，原因是缺 XCTest」，**不得声称测试通过**。

## 范围与约束

- 可写：`Packages/LegadoCore/Sources/LegadoCore/Backup/`、必要时 `Entities/`、`Packages/LegadoCore/Tests/LegadoCoreTests/`、
  `tools/backup-import-check/`（新建）、`docs/spec/backup-notes.md`。
- 不要动：`App/`、其他 `tools/` 子包、`Packages/LegadoCore` 下与备份无关的目录、`.env.local`、任何 `docs/4-*` 文件。
- 不加第三方依赖。不 commit、不 push。
- 不要把 `.build/fixtures-local/real-backup.zip` 或其解压内容复制进受版本控制的路径；它含人类的真实书架与书源数据。
- 报告里**不要粘贴备份包里的用户数据内容**（书名、书源地址、阅读记录等）；只给结构性结论与计数。
  `highlightRule.json` / `servers.json` 这两个小文件的字段结构可以描述，因为它们是配置而非个人内容。

## 完成标准

1. `swift build` 在 `Packages/LegadoCore` 与 `tools/backup-import-check` 上均通过。
2. 用新工具跑真实包：
   `swift run --package-path tools/backup-import-check ... -- .build/fixtures-local/real-backup.zip`
   失败文件列表为空（或仅剩你已论证为「Android 端也不恢复」且改为显式跳过的条目），其余计数与上面的基线一致
   （books 82、book_sources 4198、replace_rules 20、readRecord 138、bookmarks 154、book_groups 9）。
3. 报告附上该命令的原始输出末尾 20 行。

## 汇报格式

中文 markdown，不超过 70 行。结构：结论先行 / 两个条目各自的 Kotlin 语义与 `Kotlin文件:行号` 依据 /
改动文件清单（带 `Swift文件:行号`）/ 新工具用法一行 / 真实包运行的原始输出末尾 20 行 / 未验证项与未解决项。
</task>
