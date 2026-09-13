# 阶段 3 计划：MVP 界面

> 状态：**人类已通过 `/goal` 预先授权连续推进**（2026-09-13），本轮不再等待逐轮确认；方向性变更仍停机。

## 1. 结论先行

- 用 **XcodeGen** 生成 `App/Legado.xcodeproj`（`project.yml` 为真源，生成物一并提交），应用目标 `Legado`，依赖本地包 `Packages/LegadoCore`；SwiftUI + Observation，iOS 17。
- 架构：`App/Sources/` 分 `App`（入口、依赖容器、数据库生命周期）、`Features/<功能>/`（View + ViewModel）、`Shared/`（组件、主题、Keychain）。ViewModel 只依赖 LegadoCore 的 protocol（HttpClient、Repository、Importer），可用假实现单测。
- 阅读器分页用 CoreText（`CTFramesetter`）按页面尺寸与排版参数切页，先纯文本，图片后置。
- 六个单元按依赖顺序推进，每个单元 Codex 实现、独立复审、返修、提交；构建判据用 `xcodebuild` 而不是 `swift build`。

## 2. 单元划分

| 单元 | 内容 | 验证 |
| --- | --- | --- |
| **A1 工程骨架** | `project.yml`、`.xcodeproj`、App 入口、依赖容器（数据库文件路径、HttpClient、Repository）、TabView 导航（书架 / 搜索 / 书源 / 设置）、数据库挂起 / 恢复接入、书架列表读库（空态 + 列表）、打包脚本 `tools/build-ipa.sh` | `xcodebuild build CODE_SIGNING_ALLOWED=NO`；ViewModel 单测 |
| **A2 书源与替换规则管理** | 书源列表（分组、启用、搜索过滤）、导入（URL 下载 / 文件选择 / 剪贴板）、删除；替换规则列表与开关；导入结果页 | 单测：导入流程走假客户端与内存库 |
| **A3 搜索、详情、目录** | 多源并发搜索（TaskGroup、按 concurrentRate）、结果聚合去重、精准搜索开关；详情页与加入书架；目录页分页拉取、倒序、章节落库 | 单测：搜索聚合、目录落库 |
| **A4 阅读器** | CoreText 分页、翻页手势、章节切换与预取、进度持久化（`durChapterIndex` / `durChapterPos`）、字号 / 行距 / 主题、替换规则应用、章节缓存 | 单测：分页器对固定尺寸与文本的页数与断点；进度持久化 |
| **A5 设置与备份** | WebDAV 账号（Keychain）、从 WebDAV 列出并恢复备份（复用 `WebDavBackupSource`，只读）、本地 zip 导入、恢复结果展示；关于页 | 单测：恢复流程走假客户端 |
| **A6 打包与安装说明** | `tools/build-ipa.sh`（archive → 未签名 ipa）、GitHub Actions `ios.yml`（build + package test）、README 自签安装步骤（AltStore / Sideloadly） | 本机跑脚本产出 ipa |

## 3. 关键设计决策

| 决策 | 结论 | 理由 |
| --- | --- | --- |
| 工程生成 | XcodeGen，`project.yml` 为真源，`.xcodeproj` 也提交 | 无 xcodegen 的机器可直接打开；CI 可重新生成校验一致 |
| 状态管理 | Observation（`@Observable`）+ 依赖容器注入 | iOS 17 起稳定，便于 ViewModel 单测 |
| 数据库 | 文件库放 Application Support，`AppDatabase.suspend/resume` 接入场景阶段变化 | `docs/spec/storage-notes.md` 要求 |
| 网络 | 应用内统一用 `BoundedURLSessionHttpClient`（有响应上限） | U6 复审结论 |
| 凭据 | Keychain（`kSecClassGenericPassword`），不进 UserDefaults | 常规 |
| 签名 | 不配置签名，`CODE_SIGNING_ALLOWED=NO` 构建，产出未签名 ipa 交自签工具 | 分发目标为自签侧载 |
| 模拟器 | 若本机无 iOS 运行时，构建目标用 `generic/platform=iOS`，人工冒烟改由人类真机执行 | 环境事实 |

## 4. 风险

| 风险 | 缓解 |
| --- | --- |
| 阅读器分页与 Android 排版差异大 | 先纯文本与基本参数，参数名对齐 Android 配置项，后置精修 |
| Codex 沙箱内 `xcodebuild` 可能受限 | 单元报告贴原始错误；主会话代跑构建验证 |
| 并发搜索与 GRDB 写入的线程安全 | 引擎实例每任务新建；写库经 Repository 的 async 接口 |
| 本机无模拟器运行时 | A1 先探测；无则只做 generic 构建，冒烟留给人类真机 |
