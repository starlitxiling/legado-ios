# 书源宿主 API 静态统计

`analyze_sources.py` 只使用 Python 标准库，读取本地合集并向标准输出写 Markdown。不执行 JavaScript、不访问网络，不输出书源对象、标识 URL 或站名。按任务要求直接使用 `python3`，不安装依赖。

## 输入与运行

位置参数为合集目录，包含顶层对象数组形式的 `*.json` 和无表头的 `manifest.tsv`。manifest 六列依次为文件名、GitHub 仓库、仓库内路径、commit SHA、UTC 下载时间和字节数。

```sh
python3 -m py_compile tools/corpus/analyze_sources.py
python3 -B -m unittest discover -s tools/corpus -p 'test_*.py'
python3 -B tools/corpus/analyze_sources.py /private/tmp/claude-501/-Users-wujie-Work-legado-ios/d9bfa378-d458-442c-bd30-3507bcb06aea/scratchpad/corpus --date 2026-09-12 --kotlin-revision 35a485ed37dec7ac4a72b578cf2782e00adbe1a0 > docs/0-iOS适配规划/宿主API优先级.md
head -n 30 docs/0-iOS适配规划/宿主API优先级.md
```

默认 Kotlin 目录为任务提供的主 checkout 的 `app/src/main/java/io/legado/app/help`；可用 `--kotlin-dir` 覆盖。从该目录读取 JsExtensions.kt 和 JsEncodeUtils.kt，并相对其父目录读取 model/analyzeRule/AnalyzeRule.kt、model/analyzeRule/AnalyzeUrl.kt、data/entities/BaseSource.kt。词表仅包含这五个同名宿主类型的直接公开成员方法（含默认公开、override、suspend 声明），排除 private/internal/protected、同文件辅助类型、嵌套类型和 companion 扩展函数。报告同时列出原两文件全部 fun 的历史基数、原两文件公开成员数和五文件扩展数。`--kotlin-revision` 只记录调用者提供的版本，不验证文件是否有未提交修改；文件内容是实际输入。日期可显式固定以复现输出。

## 统计口径

- 每次流式解码一个书源对象，内存中仅保留按 URL 哈希标识的特性集合，不保留完整语料。`bookSourceUrl` 以原值去重，不归一化协议、路径或大小写；同键所有版本的特性取并集。空键逐条独立计数，不将不相关记录合并。
- 分母为去重源总数，任一特性每源最多计一次；不按出现次数加权，不过滤 enabled 或历史源，不执行可用性验证。
- 仅扫描 `jsLib`、`loginUrl`、`loginCheckJs`、`header`、`searchUrl`、`exploreUrl` 及五组 `rule*` 下递归字符串。书源名称、说明及其他元数据不参与扫描。
- 规则模式表统计文本标记，不做规则执行。XPath 合并 `@XPath:` 与 rule 字段的 `/` 前缀启发式；JSONPath 合并 `@json:` 和 `$.` 前缀。`&&`、`||` 等可能来自 JS 运算符，不能直接理解为规则组合器执行率。
- JS 提取 `<js>`、`@js:`、`@webjs:`、`{{ }}`、库与登录检查字段，以及 URL 选项中的 `js`、`webJs`、`bodyJs`。未标记但含直接 java 调用的字符串也作为候选；排除 `$.` 与显式规则前缀的插值，外层 JS 中的插值先屏蔽，避免把 JSONPath 后代选择误认作 E4X。模板边界使用非贪婪文本提取，不是完整嵌套语法解析。
- 在候选 JS 内屏蔽字符串、注释及可识别正则字面量后统计直接 `java.method(`。不展开动态属性、别名、eval、外部库和模板字符串内插值；WebView 脚本也计入，因此指标是迁移依赖候选，不是 JSC 调用实证。
- 累计覆盖分母为至少直接调用一个 java 方法的源。只有该源完整方法集合都在已实现集合中才算覆盖；不使用「至少命中一个方法」的并集覆盖。入口词表之外的直接调用也进入分母、排序及分级，并单列，防止虚高。这些 API 名需要后续核实接口归属与契约。
- 方法按源数降序、同频按名称排序。一级与二级为此排序达到 80% 和 95% 的最短前缀；这是给定频率顺序下的最小集合，不声称任意方法子集的全局最优。三级包括剩余公开成员候选，零频方法按后续兼容需求评估。
- Rhino 特性只做词法检测。E4X 为 XML 字面量、`.@attr` 和后代运算的并集；排除扩展运算符 `...`。`.length()` 不判断接收者类型。`String`、`CryptoJS`、`let`、`const` 是相关写法而非 Rhino 专有语义。零命中不构成不存在的证明。
- 每项最多两例，选自不同去重源，只输出最小匹配结构，所有非保留标识符匿名化，字符串和注释已屏蔽；不足两例时明确写无可用命中，不补造样例。
- URL 选项按引号和括号层级识别业务字段中逗号后的第一个顶层对象，只统计该对象顶层键；后续对象和 body、headers 等嵌套对象均不展开，js/webJs/bodyJs 只读取顶层值；严格 JSON 失败时，对疑似选项对象做引号与括号感知的键扫描，不求值、不解码其中 JS 值，并记录片段数。白名单包括 origin、resolveIp（dnsIp 的序列化别名）、serverID、webViewDelayTime；仅含未知键的对象也保留统计。未知键在「未知选项键」表中逐键计数并用哈希标签输出，以免泄漏业务标识。非标准选项中的 JS 可能漏计。
- 注入变量只统计标识符出现，不能区分局部变量、属性或遮蔽；名称出现并不证明读取了宿主注入值。

## 验证与限制

合成单测覆盖逐对象解码、重复键并集、完整依赖覆盖、注释字符串排除、五文件公开宿主成员、URL 嵌套对象隔离、新增选项键与纯未知选项对象；不使用真实书源做测试 fixture。报告来源表的 SHA 与下载时间原样取自 manifest，不进行联网复核；统计不能替代 Android 与 iOS 的运行一致性验证。
