<subagent_contract>
你是一个子代理。你的最后一条消息是唯一交付物，调用方看不到其他任何内容。必须遵守：
1. 所有发现、结论、文件路径都写进最后一条消息；禁止以计划、提问或"接下来我会…"收尾——先做完，再汇报。
2. 第一段先给结论（哪些单元完成、哪些未完成及原因），细节放后面。
3. 涉及代码的每条论断都带 `文件路径:行号` 引用。
4. 如实汇报：测试失败就原样贴失败输出末尾；跳过的步骤要说明；没验证过的事不得声称完成；报告里引用的测试名必须在仓库中真实存在。
5. 只做指派的任务：不扩 scope、不顺手重构、不 push。
6. 改代码时贴合周边代码风格；注释只写代码本身无法表达的约束。
7. 用完整句子；禁止碎片化短语、箭头链、自造缩写、表情符号。
8. 某个单元被卡住就跳过它继续做下一个，并在报告里精确说明缺什么信息；不许猜测、不许编造。
9. 关键假设失效（任务书写的现象在代码里不成立）立即记录并跳过该单元，不要硬做。
</subagent_contract>

<task>
目标：轮次 6 返修 R2。R1（`docs/6-真机体验修复/R1-REPORT.md`，终点 `cdedfce6e`）经独立复审，发现下列问题需要收尾。修完后重跑完整回归，为真机打包做准备。

工作目录：/Users/xiling/Work/legado-ios/.claude/worktrees/ios（分支 `ios`，起点 `cdedfce6e`）。
Kotlin 规格（只读）：/Users/xiling/Work/legado-ios/app/src/main/java/io/legado/app/ ，简写 `K/`。

## 单元（按顺序；每单元先红后绿，单独 commit，message 以 `[round 6 R2-Gx]` 开头，末尾附 `Co-Authored-By: Codex <noreply@openai.com>`）

**G1 [P2] 书源模糊匹配从全局查询中拆出**
- 现象（已核实）：R1-F5 把规范化匹配放进了 `Packages/LegadoCore/Sources/LegadoCore/Storage/Repositories/BookSourceRepository.swift:34-38` 的通用 `get(bookSourceUrl:)`。所有调用方都被波及，例如 `App/Sources/Features/Explore/ExploreViewModel.swift:86`、`WebApi.swift:125` 的删除路径：目标源已不在库中时会误删一个规范化后相同的其他书源；`ImageRepositoryLoader.swift:10` 每次加载缺源或本地书封面都会把全部书源网址规范化一遍。
- 期望：`get(bookSourceUrl:)` 恢复为纯精确匹配。另开一个明确命名的 API（例如 `resolveForBookOrigin(_:)`），只在「书的 origin 查书源」这一场景使用（阅读器打开书籍、以及 R1-F5 原本接入的书籍相关入口）；删除、编辑、启用、封面加载、Web API 一律走精确匹配。逐一列出 `get(bookSourceUrl:)` 的全部调用方及各自归属（精确 / 书籍 origin），写进报告。
- 接回书源时同时更新 `originName` 为该书源的 `bookSourceName`（对照 `K/` 中换源时写入 origin 与 originName 的代码，给出 `文件:行号`）；当前只改了 origin（`App/Sources/Features/Reader/ReaderViewModel.swift:166`）。
- 测试：删除一个已不存在的 `X`，库里有 `X/` 时不得删除 `X/`；书籍 origin 为 `X` 时仍能接回 `X/` 并写入 originName；R1 的四种构造用例保持通过。

**G2 [P2] 补真正的 250 ms 合并写入测试，并更正报告**
- 现象（已核实）：`R1-REPORT.md:50` 引用的 `testDefaultProgressCoalescingActuallyWritesWithoutExplicitFlush` 在仓库中不存在；现有新增测试走 `saveProgressForBackground` 直接调用 `saveProgress`，没经过 `scheduleProgressSave`（`App/Sources/Features/Reader/ReaderViewModel.swift:499` 附近）。
- 期望：新增一条测试，使用真实（或可注入但很短的）合并延迟，连续多次翻页触发 `scheduleProgressSave`，不做显式 flush，等待后断言数据库里只写入最后一次进度、且写入确实发生。然后更正 R1-REPORT.md 中错误的测试名。

**G3 [P3] 后台任务到期回调同步结束**
- `App/Sources/Features/Reader/ReaderDeviceController.swift:86` 在 `beginBackgroundTask` 的 expiration handler 里异步调用 end。改为在回调内同步 `endBackgroundTask`，并保证与正常路径的 end 不会重复调用（幂等）。测试可用可注入的后台任务接口断言 begin 与 end 恰好配对一次。

**G4 [P3] 样式损坏备份按内容去重**
- `App/Sources/Features/Reader/ReaderStyleStore.swift:71,197`：回退状态下每次打开阅读器都新存一份 `readConfig.broken-*`。改为内容相同（比较字节或哈希）时不再新建。测试：两次 load 同一份损坏内容只产生一份备份；内容不同则产生两份。

**G5 [P3] 取消判定补正向测试并核查 HeadlessWebView**
- 补一条测试：在已取消的 Task 内发起请求得到 `URLError.cancelled` 时，`isCancellation` 仍为真、界面不显示错误。
- 核查 `HeadlessWebView.swift:129-130`：WebView 导航被新导航打断时产生的 -999（`NSURLErrorCancelled`）在 R1 后是否会显示红字。如会，恢复为按取消处理（与 Android 忽略被打断导航的行为一致），并补测试；如不会，在报告里给出依据。

## 约束
- 不改 `App/project.yml` 包标识，不加依赖，不 push，不访问真实 WebDAV 写接口，不提交 `.build/fixtures-local/` 下任何内容。
- 新增 App 源文件后运行 `xcodegen generate` 并提交生成物；新增 appcore-check 源链接后 touch 其 `Package.swift`。
- 所有 shell 命令加 `rtk proxy` 前缀。

## 验证（命令从工作目录根执行，参数与 `.build/round6/r1-final-summary.md` 中的完全一致）
- 每单元：相关 Core / App 单测先红后绿，报告写红灯日志路径与失败断言名。
- 全部单元完成、最后一次 commit 之后：Core 全量、App 全量、不带 `-only-testing` 的完整模拟器测试（LegadoTests 与 LegadoUITests），日志 `.build/round6/r2-final-*.log`，并写 `.build/round6/r2-final-summary.md`（含 commit 哈希、开始时间、各 `Executed N tests, with M failures` 原文行）。N 为 0 视为未验证。
- 如沙箱阻止 xcodebuild 或模拟器：不要停下，完成全部代码与可运行的单测并 commit，在报告里列出未能运行的命令并标「未验证」。

## 交付
1. 写 `docs/6-真机体验修复/R2-REPORT.md`（不超过 80 行）：逐单元状态、commit 哈希、改动文件、红绿日志路径与 Executed 原文行；G1 的调用方归属表。
2. 更新 `docs/6-真机体验修复/PROGRESS.md`。
3. 最后一条消息：结论先行，未完成项单独列出，不超过 400 字，不回贴代码与日志全文。
</task>
