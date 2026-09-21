# P4 真实回归记录

2026-09-19，流程基础提交 `0f6d5094a`。此轮未达到 P4 的 6/8 门禁，不能据此宣布 P4 完成。

命令行共选取备份中的 40 个候选，每个运行搜索、详情、目录及前两章正文。4 个完整通过：逐浪、起点中文网、爱下电子书 app、松鹤庭沐。失败包括空接口响应、验证页面、HTTP 403/502、TLS/超时、规则取值失败及缺少 WebView。尚未把全部失败归因为书源失效。

从上述候选取 8 个在 iOS 26.5 模拟器使用真实 HeadlessWebView 复验四流程及第一章，要求正文非空白字符至少 100；结果 4/8。这是同一批候选的复验，不是新增 8 个候选，也不等同于命令行两章检查。

| 候选编号 | 结果 | 目录章节数 | 正文字数 | 失败阶段 |
| --- | --- | --- | --- | --- |
| 1 | 通过 | 148 | 2689 | - |
| 7 | 通过 | 297 | 2921 | - |
| 9 | 通过 | 851 | 2126 | - |
| 10 | 失败 | 1038 | 0 | 正文解析 |
| 12 | 失败 | 42 | 0 | 正文超时 -1001 |
| 30 | 通过 | 1674 | 4307 | - |
| 16 | 失败 | 1 | 0 | 正文解析 |
| 20 | 失败 | 0 | 0 | 目录解析 |

## 复跑

在 iOS worktree 根运行，无必需环境变量；需要 Xcode 和已安装应用的模拟器。将私有配置写入该应用数据容器的 `Documents/SourceRegression/input.json`，结构为 `{"requiredPasses":6,"candidates":[{"id":"candidate-1","keyword":"demo","source":{}}]}`，其中 source 使用完整 BookSource 对象，候选数必须不少于 requiredPasses。

```sh
rtk proxy xcodebuild -project App/Legado.xcodeproj -scheme Legado \
  -destination 'platform=iOS Simulator,name=Legado-Startup-Check' \
  -only-testing:LegadoTests/SourceRegressionTests -collect-test-diagnostics never \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO test
```

报告写到同目录 `results.json`，逐个候选原子落盘，只含编号、阶段、计数与错误类型。没有 input.json 时明确跳过测试；跳过不计真实门禁通过。复跑结束删除 input.json，避免常规单测意外访问真实网络。此次私有输入已删除。

命令行工具新增可选 `--error-log`，仅在显式指定时将原始错误写到本地文件；标准输出继续脱敏。该文件可能含地址或书源变量，只保存在忽略目录，不提交。此次原始日志位于 `.build/round5/real-sources/`，模拟器日志为 `.build/round5/p4-live-simulator.log`。

真机按计划在批次 3 和批次 5 验证；此轮未声称 iPhone 验收通过。

## 最终复验

2026-09-22 新固定候选集合 CLI 8/8、iOS 模拟器 7/8，已达到 P4 的 6/8 门槛。候选选择方法与具体编号见 [REAL-SOURCES-FINAL.md](REAL-SOURCES-FINAL.md)；上文保留早期门禁结果，不覆盖历史失败。
