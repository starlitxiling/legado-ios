# 进度（阶段 3 · MVP 界面，轮次 2）

> 新会话先读本文件。最后更新：2026-09-13 19:20（本机时钟）。

## 1. 当前位置

- 阶段 3 轮次 2，在 `ios` 分支直接开发。起点 commit：阶段 2 收口 `d1b64fd21`。
- 环境：Xcode 26.6，iOS 26.5 SDK，**无 iOS 模拟器运行时**（构建用 `generic/platform=iOS`，人工冒烟留真机），XcodeGen 2.46.0 已装。
- 人类已通过 `/goal` 授权连续推进到应用可构建。

## 2. 任务表

| 单元 | 状态 | 通道 | 产物 | 验证 |
| --- | --- | --- | --- | --- |
| A1 工程骨架（project.yml / xcodeproj / 入口 / 容器 / 导航 / 书架读库 / 打包脚本） | 在途 | Codex | `App/`、`tools/build-ipa.sh` | `xcodebuild build CODE_SIGNING_ALLOWED=NO` |
| A2 书源与替换规则管理 | 待办 | Codex | `App/Sources/Features/Sources`、`ReplaceRules` | ViewModel 单测 |
| A3 搜索、详情、目录 | 待办 | Codex | `Features/Search`、`BookDetail`、`Toc` | 单测 |
| A4 阅读器 | 待办 | Codex | `Features/Reader` | 分页器单测 |
| A5 设置与备份 | 待办 | Codex | `Features/Settings`、`Backup` | 单测 |
| A6 打包与安装说明 | 待办 | Codex | `tools/build-ipa.sh`、`.github/workflows/ios.yml`、README | 本机产出 ipa |

## 3. 在途子 agent

（派出后登记）

## 4. 下一步与未决

- A1 回收后复审、返修、提交；A2 与 A3 可并行；A4 依赖 A3；A5 依赖 A2；A6 最后。
