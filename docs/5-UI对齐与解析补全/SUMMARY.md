# 轮次 5 交付总结

## 需求与完成范围

按 Fable 的 PLAN.md，以 Kotlin `2bdd3c58b` 为规格完成 P0-P9、U0-U9 的实现、离线测试与 iOS 模拟器验证，并执行全部 4198 个备份书源的搜索冒烟及精选四流程回归。后半程按用户要求全部由主会话执行。本轮代码已交付，但不能标为计划全部验收通过：iPhone 测试按最新指示暂缓，Android 互导/并排截图受环境阻塞，真实样本覆盖与部分失败归因仍有缺口。

## 关键改动

| 单元 | 交付 |
| --- | --- |
| P0-P2 | 启动/内存/加密备份基线，组合规则、URL 末处理、空值边界，完整 JS 实体上下文与跨流程变量 |
| P3a-P3h | UI、字节、加解密/CryptoJS、时间、文件/压缩、缓存、字体、书籍刷新及并发宿主 |
| P4-P6 | WebBook 响应校验、HTML/正文/图片缓存、分页/批量内容、净化与 OpenCC、代理/DNS/multipart |
| P7-P9 | UMD/RAR/7z/AZW 与既有格式、TXT/EPUB/PDF/MOBI 对齐、书架更新/缓存，JSONPath 与共享 DOM XPath |
| U0-U3/U9 | 运行时主题、通用组件、四入口导航、七档书架与分组、搜索和范围选择 |
| U4-U6 | 发现折叠/筛选、详情与换源、阅读器覆盖菜单/样式/设置/独立目录及图片阅读 |
| U7-U8 | 书源编辑七组字段/辅助键盘/调试/选择导入/二维码，设置重排、自动任务、主题与备份配置 |

真实回归进一步修复宽松请求头、重定向 raw 响应、DOM/Java 集合桥、Date 参数、实体变量方法和登录脚本上下文，提交 `bbe2b6a5a`。兼容说明与测试证据集中于 [REVIEW.md](REVIEW.md)、`docs/spec/` 和 `assets/`。截图为 iOS 模拟器实拍，尚无 Android 并排验收。P4 去重按实际 Kotlin URL 相等语义实现，修正了计划对“全字段”的描述。

## 验证与复现

| 验证 | 结果 | 本地原始证据 |
| --- | --- | --- |
| LegadoCore | 747 项，0 失败 | `.build/round5/final-core-complete.log` |
| App 非 UI 逻辑 | 322 项，0 失败 | `.build/round5/final-app-complete.log` |
| WebBook CLI / conformance CLI | 5/5、7/7 | `.build/round5/final-smoke-complete.log`、`final-conformance.log` |
| 一致性语料 | 134/142；8 条替换预览 unsupported | conformance 日志及 Core fixture 测试 |
| 最终模拟器 UI | 25 项最终均有通过记录；首轮 23/25，修正后两类复测 8/8 | `.build/round5/final-ui.xcresult`、`final-ui-retry.xcresult` |
| 本地书 | 十格式导入并到末章，EPUB/PDF/AZW3 图片通过 | 最终 UI 的 LocalBookUITests |
| 精选真实四流程 | 17/20，达到 16/20 数量门槛 | [REAL-SOURCES-FINAL.md](REAL-SOURCES-FINAL.md) |
| P4 模拟器真实四流程 | 7/8，达到 6/8 门槛；同组 CLI 8/8 | `.build/round5/final-live8-review.xcresult` |
| iOS 构建 / Release 归档 | 成功，IPA ZIP CRC 校验通过 | `.build/round5/u8-ios.log`、`final-ipa.log` |

全部书源搜索统计如下；完整逐条编号及诊断见 [ALL-SOURCES.md](ALL-SOURCES.md)。精选集经过预检筛选，不代表全库随机通过率。

| 执行范围 | 通过 | 失败 | 超时 |
| --- | --- | --- | --- |
| 全量 4198 条首轮 | 333 | 3498 | 367 |
| 189 条修复相关重测后，与未重测条目合并 | 356 | 3449 | 393 |

未签名产物：`dist/Legado-1.0-bbe2b6a5a.ipa`，8,446,774 字节；包含所有业务代码修复，之后仅调整 UI 测试和报告。最低 iOS 17。未推送、未安装至 iPhone、未写入 WebDAV。

以下命令均在 iOS worktree 根执行。Swift 包测试需要 Swift 6.3 与仓库已解析的依赖；iOS 构建需要 macOS/Xcode。环境变量仅把缓存/临时文件放在仓库内。模拟器名称应替换为本机已有模拟器，不指定已连接手机。

```bash
rtk proxy mkdir -p .build/tmp .build/clang-cache .build/cache
rtk proxy env CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/clang-cache" TMPDIR="$PWD/.build/tmp" swift test --package-path Packages/LegadoCore --cache-path "$PWD/.build/cache" --disable-sandbox --disable-automatic-resolution --skip-update
rtk proxy env CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/clang-cache" TMPDIR="$PWD/.build/tmp" swift test --package-path tools/appcore-check --cache-path "$PWD/.build/cache" --disable-sandbox --disable-automatic-resolution --skip-update
rtk proxy xcodebuild -project App/Legado.xcodeproj -scheme Legado -destination 'platform=iOS Simulator,name=Legado-Startup-Check' -only-testing:LegadoUITests CODE_SIGNING_ALLOWED=NO test
rtk proxy bash tools/build-ipa.sh
rtk proxy python3 tools/source-regression-report.py
```

报告脚本默认读取私有 `.build/round5/{all-search,host-retry}` 结果；可用 `LEGADO_REGRESSION_DIR` 指定结果根目录。没有这些输入时会明确报错，不会生成虚假的空报告。真实书源与响应正文不进入 Git。

## 未完成验收与限制

- iPhone 中期/最终恢复、整架更新与内存峰值验收均按用户要求暂缓，不能声明达到 300 MB；详情见 [DEVICE-READING-2026-09-22.md](DEVICE-READING-2026-09-22.md)。
- 本机无 Android 设备/SDK/AVD，官方下载主站与备用域名均 TLS 失败；Android 应用恢复 iOS 备份及同屏截图未执行。离线互导测试不能替代 Android 应用验收。
- 私有备份没有纯 JS 书源；精选 loginCheckJs 两源未完成四流程。因此各特征至少两个成功真实样本的覆盖尚未满足；配置含分页/XPath 也不等于每次实际经过该分支。
- 448 个空搜索、61 个一般脚本异常、15 个响应/选择器差异、2 个未取得诊断仍需同输入 Android 对拍。另有 3 源依赖未映射的 Java IO/Security 类。未将这些条目直接判定为站点失效。
- 164 个 CLI WebView 缺失不能等同 App 不支持。网络失败具有时效性；本次修复后仅重测相关 189 源，不是第二轮全量回归。
- iOS 后台自动任务由系统调度，不能保证前台式精确执行；本地书目录配置影响后续导入，不自动搬迁旧文件。其它平台差异见 `docs/spec/`。
