# 总结：阶段 4 功能对齐（Android 全部功能 → iOS）

## 开发项背景

阶段 3 交付的是 MVP（书架 / 书源 / 搜索 / 详情 / 目录 / 阅读 / 替换规则 / 设置 / 备份导入）。人类在核对「Android 上的所有功能是否都实现了」后指示：先把全部功能做完，不急真机测试。本轮目标是把 Android 端（Kotlin，commit `cb664b84d`）剩余的功能面逐项移植到 iOS，并保持数据格式（书源 JSON、备份 zip、偏好 XML）双端互通。

## 实现方案

**工作方式**：15 个功能单元分 4 个批次，每个单元由 Codex（gpt-6-astra @ medium）实现（TDD 先红后绿）→ Codex 独立上下文只读复审（对照 Kotlin 逐条给 `文件:行号`）→ 按 Kotlin 返修 → 批次收口（合并态两套全量 + `xcodegen` + `xcodebuild`）→ 提交推送。主会话只写任务书、核验报告、决策与进度。

**单元与提交**：

| 批次 / 提交 | 单元 | 复审 finding |
| --- | --- | --- |
| 1 `1480ad923` | B1 发现页 / 封面 / 图片正文；B2 登录 / Cookie / 校验；B3 本地 TXT / EPUB | 4 / 10 / 6 |
| 2 `b603da0c2` | B4 WebView 抓取与内置浏览器；B5 纯 JS 书源；B6 听书 TTS；B7 MOBI / PDF | 3 / 4 / 10 / 4 |
| 3 `2ebc26ecf` | B8 书源编辑与管理进阶；B9 阅读器进阶；B10 书架进阶与下载 | 5 / 5 / 7 |
| 4 `981988159` | B11 RSS；B12 漫画 / 音频源；B13 备份上传；B13b 设置全集；B14 局域网 Web；B15 实体补齐 | 7 / 4 / 5 / 7 / 8 / 7 |

**关键设计决策**：

- 一律以 Kotlin 源码为规格。主会话任务书凭印象写错的多处（类型常量、偏好格式、备份文件名、默认规则集）都由 Codex 停机纠正，最终全部回源。
- 数据互通优先：偏好备份用 Android 的 SharedPreferences XML 而非 JSON；备份文件名、28 项文件清单与恢复顺序、书源 / 替换规则导出的字段顺序均与 Android 一致；设置 key 名与 `PreferKey` 一致。
- 默认资源完整移植：TXT 目录规则 26 条、字典规则 5 条、键盘辅助 32 项都来自 Android 应用自身的 assets（不是第三方书源，不违反语料合规）。
- 音频会话统一：听书（AVSpeechSynthesizer / HTTP TTS）与音频书（AVPlayer）共用所有权对象，互斥；`UIBackgroundModes: [audio, fetch]`，`BGTaskSchedulerPermittedIdentifiers` 用于书架后台刷新。
- 局域网 Web 服务只在前台运行，默认要求 `x-legado-token`，CORS 与 Android 同构。
- 测试全部离线：网络经 `HttpClient` 注入，WebDAV 写操作只对假客户端调用，真实服务器只读。

**额外产物**：`docs/spec/{entities-compat,settings-compat}.md` 对照表；`tools/appcore-check` 新增 10 余个检查目标（软链引用 App 非 UI 逻辑）；一次 HttpTTS 缓存键竞态（未排序 JSON 散列）在合并态被发现并修复。

## 局限性

- **未做真机 / 模拟器交互验证**（人类指示不急）：后台播放、锁屏控制、BGAppRefreshTask、WKWebView 真实站点行为、翻页动画手感、局域网服务实际连通性均只有单元测试与 `xcodebuild` 编译保证。
- **仍缺**：B14 的 WebSocket 调试 / 搜索接口；备用启动图标的栅格素材（Android 只有 VectorDrawable）；`customHosts`、`localPassword`（备份加密）只存偏好未生效；漫画 / 音频的视频类型只有占位。
- **复审同模型**：全部复审为 Codex 独立上下文，本会话项目级 Opus agent 定义未加载，Opus 交叉复审仍待补。
- 磁盘长期只剩 1–3 GB，`DerivedData` 多次删除重建；`~/.codex` 会话日志约 2 GB 未清理。

## 后续 TODO

1. B16 备用图标素材（VectorDrawable 栅格化）与 B17 WebSocket（已派出）。
2. 真机自签冒烟：按 `tools/build-ipa.sh` 打包，逐功能走一遍并回填 `docs/spec/*-compat.md`。
3. Opus@high 交叉复审规则引擎核心与 JS 宿主层。
4. `customHosts` 接入网络层、备份加密。
