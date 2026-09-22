# A4a 错误基础设施与中文声明

目标：补齐核心错误的中文原因与恢复建议，提供统一的用户错误模型、取消过滤、上下文与提示条，为后续按功能迁移提供基础。

实现：LocalizedErrors.swift 对核心网络、书源解析、文件、备份、WebDAV、数据库操作、正文处理与媒体错误逐类提供 LocalizedError；补齐原有只处理部分 case 或仍返回英文的实现。保留 CustomStringConvertible 调试详情，关联值中的文件名、规则编号、地址等仍可定位问题。45 种公开或内部错误类型有直接测试，三个私有实现就地补充文案。

ErrorPresentation 提供网络、证书、DecodingError 字段路径、GRDB 代码及常见文件错误的中文兜底；取消仍返回 nil。presentation(operation:subject:sourceFile:actions:) 生成 UserFacingError，包含操作标题、对象、文件与动作；errorBanner 支持关闭、动作按钮与窄屏换行。未知错误保留原文并加中文前缀。数据库提示不向界面暴露 SQL。

工程声明 zh-Hans/en，开发语言 zh-Hans，添加中文资源目录；重新生成 Xcode 工程与 Info.plist。主题颜色与名称两条英文校验文案改为中文。

迁移守门测试按文件、规范化原始行的多重集合比对允许清单，防止新调用或旧调用悄悄变形。当前代码实际有 203 行待迁移，计划的 187 为旧计数；排除明确的日志行与统一兜底的单个原文入口，其余保守纳入。后续每批迁移同步缩减清单。

验证：Core 红测试 2 项、117 处断言失败（a4a-core-red.log），App 兜底红测试 2 项、9 处断言失败（a4a-app-red.log）；修复后全量 Core 753/0、App 333/0。UI testChineseErrorBannerActionsAndSystemFilePicker 1/0，检查中文超时、书名、重试动作、关闭入口，以及系统文件选择器中文取消按钮；截图保存在 a4a-ui.xcresult。

命令：在 iOS worktree 根执行 A1-REPORT.md 的两条全量 swift test 命令；专项过滤分别为 --filter LocalizedErrorTests 和 --filter ErrorPresentationTests。rtk proxy xcodegen generate --spec App/project.yml 后，使用同一 xcodebuild 模拟器命令加以下过滤：

```text
-only-testing:LegadoUITests/ErrorPresentationUITests
```

原始末尾：`Executed 753 tests, with 0 failures`；`Executed 333 tests, with 0 failures`；`Executed 1 test, with 0 failures`、`TEST SUCCEEDED`。完整日志位于 .build/round6/a4a-{core-full,app-full,ui}.log。

自行复审：检查取消不变成用户错误、解码数组路径拼接、缺失字段补路径、SQL 不泄露、401/403/404 区分、关联值保留、中文声明生成物一致和提示条按钮无障碍标识。后续 A4b/c/d 仍需逐处提供操作语义与对象；未在本单元批量替换调用点，未安装真机。
