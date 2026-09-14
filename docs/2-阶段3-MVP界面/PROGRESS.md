# 进度（阶段 3 · MVP 界面，轮次 2）

> 新会话先读本文件。最后更新：2026-09-14 16:10（本机时钟）。

## 1. 当前位置

- 阶段 3 轮次 2，在 `ios` 分支直接开发。起点 `f4bd7208f`；A1–A6 已提交 `45adff6f5`（macOS 侧 333 测试 0 失败，iOS 编译待验证）。
- 环境：Xcode 26.6，iOS 26.5 SDK 头文件在但 **iOS 平台组件未安装**；`xcodebuild -downloadPlatform iOS`（8.5 GB）第一次在 91% 被后台任务生命周期终止，第二次因磁盘不足失败，清理 /tmp 隔离副本与 tools 下 .build 后（可用 17 GB）以 `nohup` 脱离重下（日志 `/tmp/download-ios-platform-3.log`）；XcodeGen 2.46.0 已装。
- 人类已通过 `/goal` 授权连续推进到应用可构建。

## 2. 任务表

| 单元 | 状态 | 通道 | 产物 | 验证 |
| --- | --- | --- | --- | --- |
| A1 工程骨架（project.yml / xcodeproj / 入口 / 容器 / 导航 / 书架读库 / 打包脚本） | 完成（1 轮复审 1 条修） | Codex | `App/`、`tools/build-ipa.sh` | `xcodebuild build CODE_SIGNING_ALLOWED=NO` |
| A2 书源与替换规则管理 | 完成（1 轮复审 3 条全修；appcore-check 48 项测试），待合并构建后提交 | Codex | `App/Sources/Features/Sources`、`ReplaceRules` | ViewModel 单测 |
| A3 搜索、详情、目录 | 完成（1 轮复审 4 条全修；LegadoCore 加公开事务入口 `AppDatabase.write` 与 Row 级操作，276 测试；appcore-check 33 项），待合并构建后提交 | Codex | `Features/Search`、`BookDetail`、`Toc` | 单测 |
| A4 阅读器 | 完成（1 轮复审 6 条全修；Reader 13 项测试；正文保留缩进字符以对齐 Android 进度坐标），待合并构建后提交 | Codex | `Features/Reader` | 分页器单测 |
| A5 设置与备份 | 完成（1 轮复审 2 条全修，9 项测试；WebDAV 只读约束静态审查通过），待合并构建后提交 | Codex | `Features/Settings`、`Backup` | 单测 |
| A6 打包与安装说明 | 完成（ios.yml：macos-15 / Xcode 16.4，含 Swift 6.1；build-ipa.sh 带版本与 hash；README 安装与构建段），待本机产出 ipa 验证 | Codex | `tools/build-ipa.sh`、`.github/workflows/ios.yml`、README | 本机产出 ipa |

## 3. 在途子 agent

| 任务 | 通道 | 输出 | session id | 派出时间 |
| --- | --- | --- | --- | --- |
| A2 实现会话 `01a09970-1649-7673-ba78-0dffbcc3d4ba`、A3 `01a09970-1649-77c2-80b5-360a0bccb71b`、A4 `01a09976-0c73-7dc0-bc00-7a56302b89b8`、A5 `01a09976-0a33-75d0-a1ee-c821be58a028` | — | — | — | — |
| iOS 平台组件下载 | 主会话后台 | `/tmp/download-ios-platform.log` | — | 2026-09-13 19:45 |

A1 实现会话 `01a09968-252d-7c82-9638-77e09cab5232`。

## 4. 下一步与未决

- **阶段 3 完成**：iOS 26.5 平台组件装好后，`xcodebuild build` 通过、`tools/build-ipa.sh` 产出 `dist/Legado-1.0-45adff6f5.ipa`（3.5 MB）、模拟器 `xcodebuild test` 通过、模拟器安装启动冒烟通过（截图书架空态 + 四 Tab）。SUMMARY 已写；收口配置（dist 忽略、Package 资源警告）由 Codex 处理后提交。
