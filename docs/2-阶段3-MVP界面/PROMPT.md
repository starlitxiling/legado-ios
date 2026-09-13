# 需求：阶段 3 MVP 界面

## 背景

阶段 1、2 已交付可离线测试的规则引擎、网络层、实体、WebBook 流程、GRDB 持久化与备份导入，并用真实数据验证（坚果云备份 4198 个书源导入、逐浪小说端到端抓取）。但仓库里还没有一个 iOS 应用：没有 Xcode 工程、没有界面、没有可安装的 ipa。人类的目标是「一直做到 iOS 应用可构建」并自签侧载。

## 目标（来自 `docs/0-iOS适配规划/PLAN.md` §4 阶段 3、§7）

SwiftUI 应用，最低 iOS 17，Universal（iPhone 优先，iPad 可用），依赖本地 Swift Package `LegadoCore`：

1. 书架（分组、排序、封面 / 列表两种视图、阅读进度）。
2. 搜索（多书源并发、精准搜索开关、结果聚合）与发现（书源 exploreUrl，可后置）。
3. 书籍详情（简介、来源、加入书架）、目录（分页拉取、倒序、跳转）。
4. 阅读器：CoreText 分页、左右翻页、章节切换、进度持久化、字号 / 行距 / 主题最小配置、替换规则生效。
5. 书源管理：列表、启用 / 禁用、从 URL / 文件 / 剪贴板导入 JSON、删除；替换规则列表与开关。
6. 设置与备份：WebDAV 账号（存 Keychain）、从 WebDAV 恢复备份、本地导入备份 zip。
7. 可构建产物：`xcodebuild` 生成未签名 `.ipa`，README 给自签安装步骤。

## 完成判据

- `xcodebuild -scheme Legado -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO` 通过；打包脚本产出 `.ipa`。
- 模拟器（若本机有运行时）或真机上人工走通：导入书源 → 搜索 → 加书架 → 阅读 → 退出再进入进度保留。
- 视图模型层有单测（走 LegadoCore 的假客户端与内存库），UI 层不强制单测。

## 约束

- 沿用双通道工作模式与 PROGRESS 断点续传；Xcode 工程用 XcodeGen 的 `project.yml` 生成并提交 `project.yml` 与生成的 `.xcodeproj`（便于无 xcodegen 的机器直接打开）。
- 不做 App Store 过审相关工作；后台模式按需声明。
- 不接入 WebView 抓取、TTS、本地书、RSS（阶段 4）。
