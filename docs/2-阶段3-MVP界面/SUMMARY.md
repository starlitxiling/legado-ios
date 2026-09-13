# 总结：阶段 3 MVP 界面

## 开发项背景

阶段 1、2 交付了引擎、网络、实体、WebBook、持久化与备份导入，但仓库里没有 iOS 应用：没有 Xcode 工程、界面与可安装包。人类的目标是「一直做到 iOS 应用可构建」并自签侧载。本轮把这些能力装进一个 SwiftUI 应用，并把构建、打包、CI 打通。

## 实现方案

六个单元，每个单元 Codex 实现、Codex 独立上下文复审、返修后合并提交（commit `bd4b545b4`）：

| 单元 | 内容 | 复审 finding |
| --- | --- | --- |
| A1 工程骨架 | XcodeGen `project.yml` → `App/Legado.xcodeproj`（iOS 17、Swift 5 语言模式、本地包 LegadoCore）、`AppContainer` 依赖容器、`DatabaseLifecycleCoordinator`（前后台通知里先 resume 再刷新）、四 Tab 导航、书架列表、`tools/build-ipa.sh` | 1 |
| A2 书源与替换规则 | 列表 / 分组 / 开关 / 删除；URL / 文件 / 剪贴板导入与预览（保留本地 `customOrder`、`keepEnable` 开关）、公开导入独立重定向客户端、JSON 无效与脚本书源文案区分 | 3 |
| A3 搜索、详情、目录 | 多源并发搜索（TaskGroup 上限 + 按源限流、增量发布、取消、精准搜索）、详情与加入书架、目录分页落库；换源在单事务内完成身份替换 + 目录写入 + 进度迁移，章节按标题相似度定位（LegadoCore 新增公开 `AppDatabase.write` 与 Row 级操作） | 4 |
| A4 阅读器 | CoreText 分页（后台、debounce）、阅读锚点独立于重排、正文保留段首缩进字符以对齐 Android 的 `durChapterPos` 坐标、翻页 / 切章 / 预取与真实下载取消、进度持久化、字号 / 行距 / 主题、缓存只存正文 | 6 |
| A5 设置与备份 | WebDAV 凭据整组原子存 Keychain、连接测试（PROPFIND Depth 0）、从 WebDAV 列出并只读恢复备份、本地 zip 导入、恢复结果页、开源许可页 | 2 |
| A6 打包与安装 | `.github/workflows/ios.yml`（macos-15 / Xcode 16.4、SwiftPM 缓存、两组测试、打包上传）、`build-ipa.sh` 带版本与 hash、README 自签安装与构建说明 | — |

**验证**：

- macOS 侧：LegadoCore 276 + `tools/appcore-check` 57 = 333 项测试 0 失败（ViewModel 与纯逻辑经软链编译）。
- iOS 侧（本机安装 iOS 26.5 平台组件后由主会话代跑）：`xcodebuild build`（generic/platform=iOS，无签名）通过；`tools/build-ipa.sh` 产出 `dist/Legado-1.0-bd4b545b4.ipa`（3.5 MB）；iOS 模拟器上 `xcodebuild test` 通过；应用安装到模拟器后启动成功，进程存活，截图显示书架空态与四个 Tab。

## 局限性

- 复审仍为 Codex 同模型独立上下文；Opus 交叉复审待项目级 agent 定义生效后补。
- 真机未验证（无设备与签名）；人工走通「导入书源 → 搜索 → 加书架 → 阅读 → 进度保留」只在模拟器启动层面冒烟，未做交互级 UI 测试。
- 发现页（exploreUrl）、封面图加载、图片正文、TTS、本地书、RSS 未做（阶段 4）。
- 替换规则 `@js:` replacement 走同步 JS 引擎，超时不能抢占死循环脚本；`replaceRule.previewText` 无配置存储。
- `dist/` 忽略与 Package 资源警告在收口提交中处理。
- CI 工作流未在 GitHub 上实际跑过（未推 PR / 未看 Actions 结果）。

## 后续 TODO

1. 真机自签安装冒烟（AltStore / Sideloadly），按 README 步骤走一遍并记录问题。
2. 交互级冒烟脚本（`xcrun simctl` + UI 测试目标）覆盖导入书源到阅读的主路径。
3. 阶段 4 优先级：TTS 听书 > 本地 TXT / EPUB > `@webjs:` 与 WebView 抓取 > RSS。
4. 真实书源回归（阶段 2 遗留：轻之文库目录超时、话本小说空目录）。
5. Opus 交叉复审阶段 1–3。
