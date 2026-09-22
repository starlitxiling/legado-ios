> 此为历史暂停检查点；用户已要求继续，最新进度见 PROGRESS.md。

# 2026-09-22 暂停检查点

用户要求先保存进度并暂停。禁止子代理；不要自动继续或安装真机，等待用户恢复指令。

工作目录：仓库下 `.claude/worktrees/ios`，分支 ios。最新已完成提交 `039bbbbfd`（B3 仿真交互与整章连续滚动）。A 全部、B1/B2/B3 完成；B4a 尚未提交，B4b/B4c、C1-C3 待办。计划为同目录 PLAN.md。

B4a 工作区内容：ReaderTypography.swift 新增 ReaderUnderline，支持 1...6 六种线型、正文/标题开关、颜色跟随/指定、宽度与距基线；Paginator 保存配置并排除图片书；ReaderView 在 CoreText 绘制下划线；ReaderInterfacePanel 一级下划线入口与配置页；ReaderSettings 对齐 Kotlin 0...10 宽度、0...30 距离；单元位图测试六种输出不同且开关可禁用；ReaderContinuousUITests 新增配置保持 UI 测试。

测试：先红 `.build/round6/b4a-red.log`（缺失 ReaderUnderline）；首次编译发现 CGColor 条件转换不受支持，已修正。`.build/round6/b4a-app2.log` 最终 `Executed 347 tests, with 0 failures`。UI 命令已经启动于暂停请求前，结果路径 `.build/round6/b4a-ui2.xcresult`、日志 `.build/round6/b4a-ui2.log`；该运行在保存检查点期间自然结束，最终 `Executed 1 test, with 0 failures`、`TEST SUCCEEDED`；尚未检查截图或完成自行复审。方法 `ReaderContinuousUITests/testUnderlineOptionsPersistAfterClosingPanel()`。

恢复步骤：先核验 B4a UI 结果与截图、复审下划线实现，补全 B4a 报告并单独提交；接着六槽模板编辑和状态栏图标（B4b）；网络导入、系统分享、段评 SVG 模板/缩放/颜色（B4c）；再完成 C1-C3。六槽现状：ReaderInfo.parts 优先 template，面板 tipPicker 当前选择预设会把 template 清空，需要补编辑入口及明确恢复预设行为。darkStatusIcon/day/night/eInk 已存储但尚未在 ReaderView 应用。

B3 证据：App 346/0，UI 2/0，b3-ui5.log/xcresult；系统 pageCurl 双面在非动画 setViewControllers 只传可见一面，动画传正反两面。短拖动会按 UIKit 原生判定完成，UI 已改验章首边界、双向翻页、点击翻页；中途反向松手的取消手感待用户真机体验。

所有 shell 命令需 rtk 前缀。测试从 iOS worktree 根运行，模拟器 ID AFAA07AC-5F79-4249-961C-06BE19C6086B；具体 xcodebuild/swift test 环境和命令见 B3-REPORT.md。UI 过滤必须带具体方法和括号，核验实际执行数。新增 App 源文件后 xcodegen；新增 appcore-check 源链接后 touch Package.swift。

签名仍阻塞：阶段 A Release 包 dist/Legado-1.0-a4e1f3c76.ipa 已生成，签名 errSecInternalComponent，未安装。最终阶段再准备当前版本；不要重试被自动审批拒绝的 Terminal 路径，不访问真实 WebDAV 写接口。此前未使用子代理。
