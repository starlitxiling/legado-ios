# legado-ios

Legado 阅读的 iOS 版：纯 Swift 重写的书源规则引擎与阅读器，兼容 Legado 书源格式。

## 安装

需要 iOS 17 或更高版本，支持 iPhone 和 iPad。分发方式为自签侧载。

先从本仓库 Releases 下载发布者提供的 `.ipa`（若尚无发布版本，请使用 Actions）。也可打开 Actions 中成功的「iOS 构建与离线测试」运行，在 Artifacts 下载 `Legado-unsigned-<commit>`，解压外层 ZIP 后取得 `.ipa`；下载 Actions 产物通常需要登录 GitHub，产物保留 14 天。工作流只上传 Actions 产物，Releases 需维护者另行发布。

两种自签安装路径任选其一：

1. **AltStore Classic**：在电脑安装 AltServer，将 iPhone / iPad 连接电脑并信任电脑，通过 AltServer 安装 AltStore。按设备提示信任开发者、启用开发者模式，在 AltStore 的 My Apps 中用「+」导入下载的 IPA，使用自己的 Apple 账号签名安装。后续在 AltServer 可连接时通过 AltStore 刷新签名。
2. **Sideloadly**：在电脑安装 Sideloadly，连接设备并信任电脑，将 IPA 拖入窗口，选择设备并输入自己的 Apple 账号，按提示完成签名安装。根据设备提示信任开发者并启用开发者模式；续签时重新签名安装，或配置工具的自动刷新功能。

免费 Apple 账号通常每 **7 天**需要续签，同一设备最多同时安装 **3 个**此类自签应用，AltStore 本身也占一个名额。过期后需续签才能继续打开；建议在到期前刷新，并保持同一账号与应用标识以保留数据。以上限制采用[项目分发决策](docs/0-iOS适配规划/PLAN.md#7-关键设计决策)，安装工具的具体界面与当前账号政策尚未联网复核。

## 构建

本机需要 macOS、完整 Xcode（含 iOS 平台组件）和 XcodeGen；Swift 工具链至少支持 Swift 6.1。先在 Xcode 设置中安装 iOS 平台组件，并将命令行工具选为该 Xcode。安装 XcodeGen：

```sh
brew install xcodegen
```

在仓库根目录执行：

```sh
tools/build-ipa.sh
```

脚本生成 Xcode 工程，以 `generic/platform=iOS` 归档未签名应用，输出 `dist/Legado-<版本号>-<git短hash>.ipa` 并打印路径与字节数。默认使用 Release，可用 `CONFIGURATION=Debug tools/build-ipa.sh` 切换配置。首次构建需要网络下载 SwiftPM 依赖；无须配置签名证书。版本号读取自归档应用的 `CFBundleShortVersionString`，短 hash 标识当前提交，未提交改动不反映在 hash 中。

CI 配置使用 `macos-15` 并通过 `xcode-select` 指定 Xcode 16.4；该镜像与工具链组合尚待首次 Actions 运行验证。CI 先运行 LegadoCore 与 appcore-check 的离线单元测试，再打包上传 IPA。测试不依赖真实书源或 WebDAV 账号，但工具安装和依赖下载需要联网；这些测试不替代 iOS 真机界面与侧载验证。

## 功能范围与已知限制

当前阶段实现网络文字书源的导入与管理、书架、多源搜索、详情与目录、纯文本分页阅读、阅读进度与排版设置、替换规则，以及本地 ZIP / WebDAV 备份恢复。WebDAV 当前仅用于读取与恢复备份。

尚不覆盖 Android 版的全部功能；TTS、本地 TXT / EPUB、RSS、WebView / `@webjs:` 抓取和完整图文阅读不属于本阶段交付范围。书源能否工作受规则兼容性和目标网站影响，不能保证所有 Android 书源直接可用。

兼容性边界请查阅[规则引擎](docs/spec/rule-engine.md)、[XPath](docs/spec/xpath-compat.md)、[JavaScript 宿主](docs/spec/js-host-compat.md)和[网络](docs/spec/network-compat.md)四份文档；持久化与恢复约束另见[Storage 接入](docs/spec/storage-notes.md)和[备份接入](docs/spec/backup-notes.md)。已完成阶段的验证与局限见[阶段 1 总结](docs/0-iOS适配规划/SUMMARY.md)、[阶段 2 总结](docs/1-阶段2数据与网络/SUMMARY.md)；阶段 3 尚未收口，当前验证状态见[阶段 3 进度](docs/2-阶段3-MVP界面/PROGRESS.md)。

## 目录结构

| 路径 | 用途 |
| --- | --- |
| `App/` | SwiftUI 应用、XcodeGen 工程配置与生成的 Xcode 工程，以及应用单元测试。 |
| `Packages/LegadoCore/` | 规则引擎、实体、网络、数据库与备份功能的 Swift Package。 |
| `Tests/` | Android 与 Swift 共用的一致性测试语料。 |
| `tools/` | 语料生成、功能验证和未签名 IPA 打包脚本。 |
| `docs/` | 分轮需求、计划、总结和规格接入说明。 |

## 开发流程

本项目遵循 [全局 Constitution](https://github.com/pkulijing/claude-code-global/blob/master/GLOBAL_AGENTS.md) 中定义的「需求 - 计划 - 执行 - 总结」四步开发模式，文档记录见 `docs/`。
