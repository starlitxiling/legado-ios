# 合成规则引擎一致性用例

本目录包含 100 条人工合成用例，分为 10 类；HTML / JSON fixture 内嵌于 input.document。所有内容均为自造，URL 域名仅使用 example.invalid。

**这些期望值需要在 Android 端跑一次基线校正。** 当前只做规格推导、源码静态复核与 JSON 结构校验，未运行 Android、Kotlin 或 Swift 实现；不得将本目录标记为黄金基线。

## Schema 差异与来源

沿用 ../golden/README.md 的对象结构及 string / stringList 期望类型，仅增加顶层 derivedFrom（规格章节与一开始计数的行号）和 verification（固定为 `spec-derived, not run on Android`）。id 改用 `synthetic-<类别>-<三位序号>`；kind 仍取黄金 schema 中的类型，不以文件类别替代 kind。

source 指向用于解释规则的 Kotlin 实现，而非原测试断言；source.commit 固定 cb664b84d。derivedFrom 指向当前 docs/spec/rule-engine.md，该文档第 4 行标注的来源版本是 6e08e1699。已检查相关七个 Kotlin 文件与 cb664b84d 无差异；这不代表整仓版本相同。source 不构成 Android 实测凭证。

requiresAndroid 只表示入口宿主依赖。AnalyzeRule 与 AnalyzeUrl 保守标 true；直接调用 AnalyzeByJSoup 的空规则用例为 false，但仍需要 JVM/jsoup 依赖。所有期望值都是未实测的规格推导值。

## 运行约定

每条用例新建解析器，加载 document；不共享 DOM、缓存或变量。所有 AnalyzeRule 入口默认 isUrl=false、unescape=true。不得根据 kind 猜入口，实际调用由 variables.operation 决定。

| variables 字段或取值 | 适配器需要执行的操作 |
| --- | --- |
| operation=AnalyzeRule.getString/getStringList/getElement/getElements | 对已 setContent(document) 的解析器执行同名入口，传入 input.rule。 |
| operation=AnalyzeByJSoup.getStringList | 直接调用 JSoup 层；空规则不能改走 AnalyzeRule.getStringList，后者有自己的 null 契约。 |
| projection=id | 对 getElements 的每个节点读取 id，保留顺序、重复项与空列表。 |
| projection=[1] | 对正则结果的每一行读取索引 1，即捕获组一，不拉平其他分组。 |
| getElement 且无 projection | 直接比较正则返回的组零到组 k，结果本身是 stringList。 |
| ruleData={} | 必须提供新建的、可写的 RuleDataInterface 宿主；不是省略宿主。不提供 book、chapter 或 source。 |
| operation=AnalyzeUrl | 用 rule 构造 AnalyzeUrl，baseUrl 默认为空，其他可选宿主为空；只解析，禁止发请求或加载 WebView。document 的空串表示该入口无需正文。 |
| page | 作为 AnalyzeUrl 构造参数传入整数，不是自动注入的通用 JS bindings。 |
| URL projection=url/method/charset/body | 读取解析后的对应字段；method 取枚举名称。body 比较序列化后的原始字符串，不用格式化 JSON 或重新编码的表单替代。 |
| URL projection=headerMap[X-Test] | 读取指定头的字符串值，不比较宿主自动添加的其他头。 |
| URL projection=retry.toString/useWebView.toString | 对解析后的整数或布尔值显式调用 toString，确保 string 期望类型准确。 |
| URL projection=derivedCallTimeoutMillis(readTimeoutMs).toString | 将解析后的 readTimeoutMs 交给 Android 的同名 helper，再显式转字符串；不得在适配器中复写派生公式来产生实际值。 |

URL 中的私有字段需要测试侧访问适配；本任务仅交付语料，不实现 runner。投影是新增的 variables 取值约定，不是新增顶层字段。Swift 可暴露等价解析状态；尚未验证任一已有 runner 支持上述入口或投影。replace 类运行 AnalyzeRule 的 ## / $1 语法，不运行黄金用例中的 ReplacePreview.apply。$1 用例中的 JS 段仅构造固定列表，期望值仍按规格 §7.3 推导。

## 覆盖矩阵

以下每行对应一个可独立运行的用例；正常情况与边界在特征描述中明确标注。黄金用例已有少量 textNodes 与索引用例，本批保留相应对照，并扩展到私有首词、区间步长、组合入口、模板、路径、正则和 URL 选项。

| 特征 | 用例 id |
| --- | --- |
| 顺序拼接。 | `synthetic-combine-001` |
| 拼接空首项。 | `synthetic-combine-002` |
| 首个非空即停止。 | `synthetic-combine-003` |
| 空首项回退。 | `synthetic-combine-004` |
| 以短首项截断后续长列表。 | `synthetic-combine-005` |
| 交错组合空首项的入口差异。 | `synthetic-combine-006` |
| 顺序拼接。 | `synthetic-combine-007` |
| 拼接空首项。 | `synthetic-combine-008` |
| 首个非空即停止。 | `synthetic-combine-009` |
| 空首项回退。 | `synthetic-combine-010` |
| 以短首项截断后续长列表。 | `synthetic-combine-011` |
| 交错组合空首项的入口差异。 | `synthetic-combine-012` |
| class 首词正常匹配。 | `synthetic-default-001` |
| class 首词无匹配边界。 | `synthetic-default-002` |
| tag 首词正常匹配。 | `synthetic-default-003` |
| tag 首词无匹配边界。 | `synthetic-default-004` |
| id 首词正常匹配。 | `synthetic-default-005` |
| id 首词无匹配边界。 | `synthetic-default-006` |
| text 首词匹配自身文本。 | `synthetic-default-007` |
| text 首词无匹配边界。 | `synthetic-default-008` |
| children 首词选择直接子元素。 | `synthetic-default-009` |
| children 在叶子节点上为空。 | `synthetic-default-010` |
| 旧式首项索引。 | `synthetic-default-011` |
| 旧式末项索引。 | `synthetic-default-012` |
| 旧式冒号表示独立索引。 | `synthetic-default-013` |
| 旧式越界索引丢弃。 | `synthetic-default-014` |
| 新式闭区间包含终点。 | `synthetic-default-015` |
| 零步长按列表长度处理。 | `synthetic-default-016` |
| 负步长绝对值过大时取一步；索引三重复去重。 | `synthetic-default-017` |
| 新式排除首尾。 | `synthetic-default-018` |
| 旧式排除所有项。 | `synthetic-default-019` |
| 新式区间两端同侧越界。 | `synthetic-default-020` |
| 新式单侧越界钳制。 | `synthetic-default-021` |
| text 合并后代文本。 | `synthetic-default-022` |
| textNodes 将直接文本节点合成单项。 | `synthetic-default-023` |
| textNodes 无直接文本节点。 | `synthetic-default-024` |
| ownText 不含后代文本。 | `synthetic-default-025` |
| ownText 无自身文本。 | `synthetic-default-026` |
| html 删除 script 和 style 后返回外层 HTML。 | `synthetic-default-027` |
| html 保留空元素外层标记。 | `synthetic-default-028` |
| all 返回外层 HTML。 | `synthetic-default-029` |
| all 保留空元素标记。 | `synthetic-default-030` |
| 属性值去重并跳过空白。 | `synthetic-default-031` |
| 属性缺失为空列表。 | `synthetic-default-032` |
| 嵌套 @ 链逐级选择后拉平。 | `synthetic-default-033` |
| 底层 JSoup 空规则直接返回空列表。 | `synthetic-empty-001` |
| 空规则无段，元素归一为空列表。 | `synthetic-empty-002` |
| 空 HTML 文档无匹配。 | `synthetic-empty-003` |
| 空 HTML 文档单串结果归一为空串。 | `synthetic-empty-004` |
| JSONPath 数组取值。 | `synthetic-jsonpath-001` |
| JSON 前缀取数组首项。 | `synthetic-jsonpath-002` |
| JSONPath 空数组。 | `synthetic-jsonpath-003` |
| JSONPath 空数组回退。 | `synthetic-jsonpath-004` |
| JSONPath 首个非空数组短路。 | `synthetic-jsonpath-005` |
| CSS 前缀正常选择。 | `synthetic-prefix-001` |
| CSS 前缀不区分大小写且无匹配为空。 | `synthetic-prefix-002` |
| 双 @ 前缀强制 Default。 | `synthetic-prefix-003` |
| 双 @ 前缀无匹配为空。 | `synthetic-prefix-004` |
| 正则列表投影分组一。 | `synthetic-regex-001` |
| 正则无匹配返回空列表。 | `synthetic-regex-002` |
| 单对象入口保留组零与所有分组。 | `synthetic-regex-003` |
| 列表入口未参与分组归一为空串。 | `synthetic-regex-004` |
| 多正则先拼接组零再运行末正则。 | `synthetic-regex-005` |
| 纯替换段替换全部匹配。 | `synthetic-replace-001` |
| 全部替换无匹配保留原文。 | `synthetic-replace-002` |
| 首匹配模式返回改写的匹配子串。 | `synthetic-replace-003` |
| 首匹配模式无匹配返回空串。 | `synthetic-replace-004` |
| 替换串支持捕获组引用。 | `synthetic-replace-005` |
| 无效正则退化为字面替换。 | `synthetic-replace-006` |
| 列表结果的 $1 模板回填。 | `synthetic-replace-007` |
| 列表过短时 $1 不插入文本。 | `synthetic-replace-008` |
| 整数内插无小数部分。 | `synthetic-template-001` |
| null 内插不插入文本。 | `synthetic-template-002` |
| 内插可嵌入规则。 | `synthetic-template-003` |
| 模板出现在替换之前使整段变为文本。 | `synthetic-template-004` |
| 缺失变量返回空串。 | `synthetic-template-005` |
| 同一段先写变量再展开模板。 | `synthetic-template-006` |
| 空子规则结果写入变量后读取为空。 | `synthetic-template-007` |
| method 转大写。 | `synthetic-url-001` |
| 未知 method 回退 GET。 | `synthetic-url-002` |
| 显式字符集。 | `synthetic-url-003` |
| escape 特殊字符集标识被保留，不断言未确定的编码细节。 | `synthetic-url-004` |
| 对象请求头。 | `synthetic-url-005` |
| JSON 字符串请求头。 | `synthetic-url-006` |
| 对象 body 按 GSON pretty printing 序列化。 | `synthetic-url-007` |
| 空数组 body 序列化。 | `synthetic-url-008` |
| 重试次数正常值。 | `synthetic-url-009` |
| 未设置重试次数默认零。 | `synthetic-url-010` |
| 字符串零为真。 | `synthetic-url-011` |
| 字符串 false 为假。 | `synthetic-url-012` |
| 超时下界派生为六万毫秒。 | `synthetic-url-013` |
| 数字串超时派生为两倍。 | `synthetic-url-014` |
| 超时派生结果钳制整型上限。 | `synthetic-url-015` |
| 宽松 JSON 解析非引号键与单引号值。 | `synthetic-url-016` |
| page 正常内插。 | `synthetic-url-017` |
| page 以构造参数注入；零也直接内插。 | `synthetic-url-018` |
| 斜线前缀的基础属性路径。 | `synthetic-xpath-001` |
| 斜线前缀无匹配。 | `synthetic-xpath-002` |
| XPath 显式前缀取属性。 | `synthetic-xpath-003` |
| XPath 属性缺失。 | `synthetic-xpath-004` |

## 边界与不纳入范围

不为规格 §11 L362-L368 的 U1-U7 建立断言：不使用省略美元前缀的 JSONPath、不断言缺失路径的异常类、不测试大写属性、空 CSS 前缀 data()、复杂替换转义、负零与超大浮点、查询编码特殊字符或 XPath 扩展函数。XPath 仅采用基础属性路径，避免文本扩展函数。

规格 §4 L136 将正则分组概括为“空组为空串”，需要区分入口：AnalyzeByRegex.kt:20 的 getElement 对未参与匹配的可选组使用 `!!`，getElements 在 :47 使用 `?: ""`。本目录的可选组边界仅走 getElements，不推导单对象入口的异常。

规格 §10.4 L308 只写“宽松解析”，未枚举允许的非标准 JSON 写法。本目录的单引号与无引号键用例对应源码 AnalyzeUrl.kt:259 的严格优先、宽松回退；Gson 的 [JsonReader 原文](https://raw.githubusercontent.com/google/gson/main/gson/src/main/java/com/google/gson/stream/JsonReader.java) 在 setStrictness 的说明中明确列出这两种宽松写法。该条仍未经 Android 实测。规格 §10.5 L318 未规定 body JSON 的缩进；源码 GsonExtensions.kt:44 开启 pretty printing，所以对象 body 用例保留两空格缩进和换行。规格 §5.3 L158-L159 未详细规定 outerHtml 的排版，本目录只使用单个最小内联元素，避免多元素换行及缩进快照。

## 五条静态复核

| 用例 | 规格与 Kotlin 复核 | 推导结果 |
| --- | --- | --- |
| synthetic-default-017 | §5.5 L178-L184；AnalyzeByJSoup.kt:336、:361、:364。长度为 4，负索引 -1 为 3；3:-2 的终点为 2；-10 归一步长 1，重复索引 3 去重。 | ["3", "2"]。 |
| synthetic-combine-012 | §6 L205-L212；AnalyzeByJSoup.kt:169、:177。元素入口保留空首列表，交错迭代零次。 | []。 |
| synthetic-replace-003 | §7.2 L226；AnalyzeRule.kt:549、:555。首个匹配是 12，仅改写该子串。 | "X"。 |
| synthetic-template-006 | §8 L254-L258；AnalyzeRule.kt:507、:814。先用整个文档取标题 A 写入 n，再展开 get。 | "A"。 |
| synthetic-url-014 | §10.5 L324；AnalyzeUrl.kt:286；AnalyzeUrlNetworkOptions.kt:77。数字串 40000 被解析后加倍，超过下限且不触及上限。 | "80000"。 |

以上是原文与源码的静态对照，不是运行 Kotlin 得到的输出。
