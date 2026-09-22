# A2 缺源与后台换源

目标：无书源时仍能打开阅读菜单、关闭提示和立即返回；自动换源在后台执行，60 秒整体超时，可主动停止。

实现：LocalBook.isLocal 对齐 Kotlin 2bdd3c58b 的 type==0 来源回退与非零类型位判定。无源且无目录时使用内存章节，不写入伪目录；加载缺源后正常排版占位正文，禁止占位页覆盖原有阅读进度。换源有独立状态、取消与超时，成功验证正文后才切换书籍；旧请求与离开阅读后的结果不会打开新正文。返回先关闭界面，进度同步在后台继续。错误提示可关闭，并提供重试、换源、书源管理与返回。

规格核实：BackupImporter.normalizeBook 已将历史类型规范化，并按本地来源补 256 位，因此计划关于恢复后仍留下 type==0 的推断不能当作已证实根因。直接读取历史 type==0 仍由本次回退覆盖。原有四项测试构造的本地/网络书类型不符 Kotlin，改为显式设置 264/8。

测试先红：a2-core-red.log 的历史来源用例失败，a2-app-red.log 的缺源占位与输入用例失败。修复后 Core 全量 751/0（a2-core-full2.log），App 全量 329/0（a2-app-full2.log），换源专项 6/0（a2-review.log）。超时用例使用不响应取消的假请求，注入到期信号后调用仍能返回；关闭时的迟到请求不改变书籍。占位正文重新排版后仍不修改保存的偏移。

模拟器 ReaderInterfaceUITests 全组 8/0（a2-ui2.log、a2-ui2.xcresult），覆盖缺源提示关闭、菜单和立即返回，并回归样式、双页、图片、高亮与书签。首轮发现父容器无障碍标识覆盖按钮标识，修复后通过。

命令均在 iOS worktree 根执行；缓存变量与完整全量命令沿用 A1-REPORT.md。专项 swift test 加 --filter ReaderSourceRecoveryTests；UI 使用同一 xcodebuild 工程、scheme、模拟器与 CODE_SIGNING_ALLOWED=NO，过滤参数为：

```text
-only-testing:LegadoUITests/ReaderInterfaceUITests
```

原始末尾：`Executed 751 tests, with 0 failures`；`Executed 329 tests, with 0 failures`；`Executed 8 tests, with 0 failures`、`TEST SUCCEEDED`。

自行复审：检查取消与计时器竞争、一次性 continuation 完成、旧任务隔离、切换前正文验证、占位进度保护及尺寸变化时排版交接。用户禁止子代理，未做代理交叉复审。超时保证调用方结束等待；底层客户端若不响应取消，其请求只能等待客户端自行结束。没有使用真实 WebDAV 凭据，没有安装本轮真机包。
