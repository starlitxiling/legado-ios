# 最终真实书源回归（2026-09-22）

## 方法与门槛

用户备份包含 4198 个书源条目，mainJs 非空样本为 0，loginCheckJs 非空样本为 25。先对全部条目各搜索一次，再从特征候选与搜索通过集取 120 个进行四流程预检，预检 65 通过、54 失败、1 超时。最后固定 20 个配置覆盖较完整的候选重新执行；这是经预检筛选的可用集，不代表全部书源的随机通过率。

CLI 每源搜索一次、取首个搜索结果、加载详情及完整目录、读取前两篇非卷章节；请求超时 15 秒、进程上限 90 秒。通过要求正文非空，图片源可返回图片标记，不能据此声称每张远端图片均已下载。最终 17/20 通过，达到 16/20 数量门槛。

配置覆盖包含 JS、JSONPath、XPath、多页目录、多页正文、图片正文各至少 2 个；loginCheckJs 的两个样本未完成四流程，纯 JS 真实样本不存在，故功能覆盖要求尚未全部满足。已有 JsSourceTests/JsSourceReviewTests 的合成测试只能证明离线契约，不冒充真实网络样本。

## 精选集

编号是私有 bookSource.json 的零起始下标。正文与私有书源配置不提交。

| 编号 | 配置特征 | 最终结果 | 章节数 | 正文字数（前两章） |
| --- | --- | --- | --- | --- |
| 426 | JS、JSONPath、图片正文 | pass | 255 | 228, 228 |
| 3780 | 图片正文 | pass | 1 | 927 |
| 105 | JSONPath | pass | 299 | 2921, 2301 |
| 195 | JS、JSONPath | pass | 423 | 2367, 2149 |
| 43 | JS、XPath、多页目录配置、多页正文配置 | pass | 535 | 2395, 4012 |
| 45 | 多页目录配置、多页正文配置 | pass | 144 | 1789, 1985 |
| 46 | JS、多页目录配置、多页正文配置 | pass | 328 | 2031, 2135 |
| 91 | JS、多页目录配置、多页正文配置 | pass | 395 | 2094, 2205 |
| 365 | JS、JSONPath、XPath | pass | 166 | 1195, 1211 |
| 30 | JS、多页目录配置 | fail | - | - |
| 16 | 常规规则 | pass | 1 | 1198 |
| 464 | JSONPath | pass | 1125 | 2781, 2003 |
| 117 | 常规规则 | pass | 19 | 5487, 29004 |
| 94 | 多页正文配置 | pass | 128 | 6242, 7975 |
| 9 | JS、JSONPath | pass | 643 | 4061, 4007 |
| 6 | JS、JSONPath | pass | 980 | 4067, 3263 |
| 200 | JS、多页正文配置 | pass | 1150 | 427, 25 |
| 170 | JS、多页正文配置 | pass | 84 | 795, 913 |
| 123 | 多页目录配置、多页正文配置、登录校验 | fail | - | - |
| 137 | JS、多页目录配置、登录校验 | timeout | - | - |

条目 30 搜索阶段 HTTP 401；123 需要 CLI 不具备的 WebView；137 达到进程超时上限。XPath 配置来自 43 的 ruleSearch.author 与 365 的 ruleBookInfo 字段，未把普通 URL 中的双斜线计入。特征列表按配置字段记录，不能仅凭规则存在断言每次请求都经过多页或 XPath 分支。

## P4 模拟器门禁

固定 8 个候选 105、195、43、45、91、365、16、117，在 iOS 模拟器运行相同核心 WebBook 四流程，要求正文至少 100 个非空白字符。7/8 通过，43 在搜索阶段发生 RequestError；达到至少 6/8 的门槛。CLI 对同一组本轮 8/8 通过。该集合由 120 个预检候选选出，替代早期不满足门槛的集合；旧报告保留历史事实。

原始证据：`.build/round5/final20-final/results.jsonl`、`.build/round5/final-simulator8.json`、`.build/round5/final-live8-review.xcresult`。

## 全量搜索与修复

全量首轮 333 通过、3498 失败、367 超时；189 个受影响条目重测后合并为 356 通过、3449 失败、393 超时。完整逐条记录见 [ALL-SOURCES.md](ALL-SOURCES.md)。重测增加的通过主要来自宽松请求头、DOM/Java 集合、重定向 raw 请求、Date 参数与脚本上下文修复；不是修复后全量重跑。

仍有 3 个样本依赖未实现的 Java IO/Security 原生类。空结果、一般脚本错误及不匹配响应需要 Android 同输入对拍进一步定位；本轮保留待核状态。CLI 缺少 WebView 的结果不能代表 App WebView 结果。

## 复现

在 iOS worktree 根运行，已导出书源 JSON 存放在私有目录，按编号导出单条数组后调用：

```bash
rtk proxy swift run --package-path tools/webbook-smoke WebBookSmoke --source .build/round5/all-search/105.json --keyword 我的 --chapters 2 --timeout 15
rtk proxy python3 tools/source-regression-report.py
```

冒烟命令把 `--chapters 2` 换为 `--search-only true`，关键词实际使用 ruleSearch.checkKeyWord，缺失时使用“我的”。报告脚本默认读取 `.build/round5`；可用 `LEGADO_REGRESSION_DIR` 指定其它结果目录。网络结果有时间敏感性，重测不保证相同。
