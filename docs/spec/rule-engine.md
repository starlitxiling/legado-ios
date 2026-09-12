# Legado 书源规则引擎规格（语言无关）

> 来源：Legado Android 版 `app/src/main/java/io/legado/app/model/analyzeRule/` 与 `constant/AppPattern.kt`，
> commit **`6e08e1699`**。所有 `（文件.kt:行号）` 均指该 commit 下的源码行。
> 本文是 iOS 纯 Swift 重写的唯一真源；Swift 实现者只读本文。示例均按源码推导，标注「未确定，需实测」者尚未在真机验证。
> 第三方依赖语义（jsoup 1.23.2 CSS 选择器、JsoupXpath 2.5.3、Jayway JsonPath 3.0.0、Rhino JS）不在本文定义范围内，本文只定义引擎如何调用它们。

## 1. 概述与术语

| 术语 | 含义 |
| --- | --- |
| 规则串 | 书源某字段的原始字符串，如 `class.book@a@href##/$##` |
| 内容（content） | 待解析对象：字符串 / HTML 节点 / JSON 文本 / JS 对象 / 列表 |
| 模式（Mode） | 六种：`XPath, Json, Default, Js, Regex, WebJs`（AnalyzeRule.kt:849-851） |
| 段（SourceRule） | 规则串按 JS 块切开后的一个片段，各自有模式、`##` 替换、`@put` 表、`{{}}`/`@get`/`$n` 模板参数（AnalyzeRule.kt:647-847） |
| 选择器组合 | 同一段内用 `&&` / `\|\|` / `%%` 连接的多个选择器 |
| 变量 | `@put` / `@get` / JS `java.put/get` 读写的键值，字符串类型 |
| 四类求值入口 | `getString`（单串）、`getStringList`（串列表）、`getElement`（单对象）、`getElements`（对象列表） |

求值总流程：规则串 → ① 切段（`splitSourceRule`）→ ② 每段：`@put` 求值 → 模板回填（`makeUpRule`）→ 按模式求值 → `##` 替换 → 结果喂给下一段 → ③ 末处理（换行拆分、HTML 反转义、URL 绝对化）。

## 2. 规则串词法

### 2.1 第一层：JS 块切段（AnalyzeRule.kt:593-636）

```
JS_PATTERN    = <js>([\w\W]*?)</js> | @js:([\w\W]*)     大小写不敏感 （AppPattern.kt:7-8）
WebJS_PATTERN = @webjs:([\w\W]{5,})                     大小写不敏感 （AppPattern.kt:9-10）
```

1. 若入口为 `getElement/getElements`（allInOne=true）且规则以 `:` 开头 → 去掉 `:`，本段与后续所有段基模式 = `Regex`，并把实例级标志 `isRegex` 置真（AnalyzeRule.kt:599-605）。**该标志是黏性的**：同一解析器实例之后的任何规则（含 `getString`）基模式都变为 `Regex`。
2. 逐个匹配 `JS_PATTERN`：匹配前的文本按 `<= ' '` 的字符 trim 后非空则成为基模式段；匹配本身成为 `Js` 段，取 `@js:` 组或 `<js>` 组（AnalyzeRule.kt:607-617）。`@js:` 一直吞到串尾。
3. 再匹配 `WebJS_PATTERN`（从 0 开始扫全串，但只有起点 > 当前游标的前置文本才会被切成段），匹配成为 `WebJs` 段（AnalyzeRule.kt:618-628）。
4. 剩余尾巴 trim 非空 → 基模式段（AnalyzeRule.kt:629-634）。

示例：`class.a@text<js>result.trim()</js>` → 段 1 `class.a@text`(Default)，段 2 `result.trim()`(Js)。

### 2.2 第二层：段内前缀识别（AnalyzeRule.kt:661-696，按顺序首个命中即止）

| 序 | 条件 | 模式 | 剩余规则 | 大小写 |
| --- | --- | --- | --- | --- |
| 0 | 段模式已是 Js / Regex | 不变 | 原样，**不再识别任何前缀** | — |
| 1 | 以 `@CSS:` 开头 | Default | 原样（含前缀，由 JSoup 层剥离） | 不敏感 |
| 2 | 以 `@@` 开头 | Default | 去 2 字符 | — |
| 3 | 以 `@XPath:` 开头 | XPath | 去 7 字符 | 不敏感 |
| 4 | 以 `@Json:` 开头 | Json | 去 6 字符 | 不敏感 |
| 5 | 内容是 JSON **或** 以 `$.` / `$[` 开头 | Json | 原样 | 敏感 |
| 6 | 以 `/` 开头 | XPath | 原样 | — |
| 7 | 其他 | 保留传入模式（包括 WebJs，AnalyzeRule.kt:626, 695） | 原样 | — |

「内容是 JSON」：`setContent` 时若内容不是 HTML 节点，则 trim 后首尾为 `{}` 或 `[]` 即判为 JSON（AnalyzeRule.kt:107-110；StringExtensions.kt:48-56）。因此 JSON 内容下无前缀的 `//a` 也走 Json（第 5 条先于第 6 条）。

### 2.3 第三层：`@put` 剥离（AnalyzeRule.kt:516-539, 1027）

`@put:(\{[^}]+?\})`（大小写不敏感）每个匹配从规则中**删除**，括号内按 JSON 对象解析为 `键→子规则` 表：先严格 JSON，失败再宽松 JSON（宽松成功仅记一次日志）。JSON 中不能出现嵌套 `}`。

### 2.4 第四层：模板参数拆分（AnalyzeRule.kt:698-741, 744-773, 1029-1030）

```
evalPattern  = @get:\{[^}]+?\} | \{\{[\w\W]*?\}\}    大小写不敏感（非贪婪，{{}} 不可嵌套）
regexPattern = \$\d{1,2}
```

- 若存在 `@get:{}`/`{{}}`，且段模式不是 Js/Regex，且（匹配在位置 0 **或** 其前文本不含 `##`）→ 段模式改为 **Regex**（AnalyzeRule.kt:706-710）。Regex 模式在 getString 中的含义是「规则文本本身即结果」（见 §4），即整段退化为字符串模板。
- 参数序列按出现顺序记录：`@get:{key}` → 类型 GET，参数 `key`（取第 6 个字符到倒数第 2 个）；`{{expr}}` → 类型 JS，参数 `expr`；其余文本交给 `splitRegex`。
- `splitRegex`：只在文本的首个 `##` 之前查找 `$n`（n 为 1~2 位数字）；找到且模式非 Js/Regex → 模式改 Regex。`$n` 记为类型 n（**`$0` 记为 0，与普通文本同型，不会被回填**），其余文本记为类型 0。
- 空白处理：段两端按 `<= ' '` trim；`makeUpRule` 后 `##` 前的规则再 `trim()`（AnalyzeRule.kt:825）。

## 3. `RuleAnalyzer` 切分算法（RuleAnalyzer.kt）

状态：`queue`（原串）、`pos`、`start`、`startX`、`rule`（结果列表）、`step`（分隔符长度）、`elementsType`（生效的分隔符）、`code` 标志（JSON/JS 时为真，选用代码平衡组）。

### 3.1 基础操作

| 操作 | 语义 | 来源 |
| --- | --- | --- |
| `trim()` | 若当前字符是 `@` 或 `< '!'`（空白/控制符），连续跳过并把 `start/startX` 推到首个有效字符。**全串都是此类字符时越界抛异常** | RuleAnalyzer.kt:15-22 |
| `consumeTo(seq)` | `start=pos`；从 pos 起 `indexOf(seq)`（区分大小写），命中则 `pos=命中位置` | RuleAnalyzer.kt:35-43 |
| `consumeToAny(seqs)` | 逐字符前进，每个位置按参数顺序试所有分隔符，**最早位置**命中者胜；置 `step` | RuleAnalyzer.kt:49-66 |
| `findToAny(chars)` | 返回 pos 起首个 `[` 或 `(` 的位置，无则 -1 | RuleAnalyzer.kt:73-85 |
| `chompRuleBalanced(o,c)` | 规则平衡组：`'`/`"` 内一切忽略（引号内**无**转义）；引号外 `\` 跳过下一字符；`o` 深度 +1、`c` 深度 −1，回到 0 结束；串尽未平衡返回假 | RuleAnalyzer.kt:131-153 |
| `chompCodeBalanced(o,c)` | 代码平衡组：任何位置 `\` 都跳过下一字符；引号同上；`[`/`]` 作为主深度，只有主深度为 0 时才计 `o`/`c` 的次深度；两者皆归零才结束 | RuleAnalyzer.kt:91-123 |

### 3.2 `splitRule(分隔符…)` 伪代码（RuleAnalyzer.kt:165-317）

```
splitRule(seps):
  if len(seps)==1:                       # 单分隔符（"@"）
     elementsType = seps[0]
     if !consumeTo(sep): rule += queue[startX:]; return rule
     step = len(sep); goto NEXT
  if !consumeToAny(seps): rule += queue[startX:]; return rule   # 无分隔符：elementsType 保持 ""
  NEXT:
  end = pos; pos = start
  loop:
    st = findToAny('[','(')
    if st == -1 or st > end:            # 分隔符不在括号内
       rule += queue[startX:end]; elementsType = queue[end:end+step]; pos = end+step
       while consumeTo(elementsType) and (st==-1 or pos<st): rule += queue[start:pos]; pos += step
       if st != -1 and pos > st: startX = start; goto NEXT      # 后段落入括号区，重新按括号法扫
       rule += queue[pos:]; return rule
    pos = st; 用 chompBalanced 吞掉整个括号组（不平衡 → 抛错 "…后未平衡"）
  while end > pos                        # 分隔符被括号包住则继续找下一个
  start = pos; 再次 consumeTo/consumeToAny 递归
```

要点：
- **只承认第一个被找到的分隔符类型**。`a&&b||c` → `["a", "b||c"]`，`elementsType="&&"`。
- 括号（`[]`、`()`）与引号内的分隔符不切。`div:matches(a||b)@text||p@text` → `["div:matches(a||b)@text", "p@text"]`。
- `throw` 是唯一的错误出口，调用方不捕获。

### 3.3 `innerRule`

- `innerRule("{$.", fr)`（RuleAnalyzer.kt:308-335）：找到 `{$.`，用代码平衡组吞到配对 `}`，把 `{ … }` 内文本（去首尾各 1 字符）交给 `fr`；`fr` 返回非空则替换，否则该 `{$.` 视为普通文本、跳过 3 字符继续。**一次替换都没发生时返回空串**（调用方据此判断「无内嵌规则」）。
- `innerRule(startStr, endStr, fr)`（RuleAnalyzer.kt:339-364）：非嵌套地找 `startStr…endStr`，内文交 `fr`，替换结果拼接；无匹配返回原串。用于 URL 的 `{{ }}`。

## 4. 六种模式的求值语义

对每段：`putRule(putMap)`（每个 `@put` 值用 `getString` 对**整个内容**求值后写入变量，AnalyzeRule.kt:507-511）→ `makeUpRule(当前结果)` → 若当前结果为 null 则跳过本段 → 按下表求值 → `##` 替换。

| 模式 | getString（AnalyzeRule.kt:343-360） | getStringList（:250-270） | getElement（:395-412） | getElements（:459-476） |
| --- | --- | --- | --- | --- |
| Default | JSoup `getString`（isUrl 时 `getString0` 只取首项） | JSoup `getStringList` | JSoup `getElements` | JSoup `getElements` |
| XPath | XPath `getString` | XPath `getStringList` | XPath `getElements` | 同左 |
| Json | JsonPath `getString` | JsonPath `getStringList` | JsonPath `getObject` | JsonPath `getList` |
| Js | `evalJS(rule, result)` | 同左 | 同左 | 同左 |
| WebJs | WebView 执行返回串 | 返回串若是 JSON 字符串数组则解析，否则原串 | 解析为 JSON 对象 | 解析为 JSON 对象数组 |
| Regex | **规则文本本身**（模板） | 规则文本本身 | `AnalyzeByRegex.getElement`，正则列表 = 规则按 `&&` 普通切分、trim、去空 | `AnalyzeByRegex.getElements` |

补充规则：
- getString 中仅当 `rule` 非空白 **或** 无 `##` 替换时才求值；即 `##a##b` 形式的纯替换段直接对上一段结果做替换（AnalyzeRule.kt:346）。getStringList 的条件是 `rule` 非空（:254）。
- **getElements / getElementsRaw 不调用 `makeUpRule`**（AnalyzeRule.kt:459-462, 428-431）：列表规则不支持 `##`、`{{}}`、`@get`、`$n`（`##` 会原样传给选择器），但 `@put` 仍被剥离并求值。getElement 会调用 `makeUpRule`，且替换作用于 `result.toString()`（:413-415），会把对象变成字符串。
- 内容为 JS 对象（`NativeObject`）时只用**第一段**：Js → evalJS；Json → JsonPath；有多于 1 个模板参数 → 规则文本；否则 `对象[规则]` 直接取键（AnalyzeRule.kt:325-336, 221-244）。内容为 Gson 映射时直接 `映射[第一段规则]`，**不做 put / 模板 / 替换**（:337-340, 245-247）。
- 末处理：getString 结果 null → `""`；`unescape` 为真且含 `&` 则做 HTML4 反转义（:367-372）；isUrl 时空白 → `baseUrl`（无则 `""`），否则相对 `redirectUrl` 绝对化（:374-380）。getStringList：字符串结果按 `\n` 拆成列表（:279-281）；isUrl 时逐项绝对化并去空、去重（:282-294）；非列表非字符串 → null。
- getElements 结果归一：列表去 null；JS 数组转列表；其余（含字符串）→ 空列表（AnalyzeRule.kt:478-502）。
- AnalyzeByRegex（AnalyzeByRegex.kt:9-59）：多个正则依次作用，前 n−1 个把所有匹配（组 0）拼接成新文本；最后一个正则：getElement 取首个匹配的组 0..k；getElements 取每个匹配的组 0..k（空组为 `""`）。无匹配 → null / 空列表。

示例：内容 `<p>A</p>`，规则 `:<p>(.*?)</p>` 经 getElements → `[["<p>A</p>", "A"]]`；随后字段规则 `$1` 因 `isRegex` 黏性走 Regex 模式，`makeUpRule` 用当前元素列表回填 → `"A"`。

## 5. Default 模式（JSoup 私有语法）

### 5.1 文档解析（AnalyzeByJSoup.kt:21-34；SourceHtmlParser.kt:9-16）

HTML 节点直接用；字符串以 `<?xml`（不敏感）开头 → XML 解析器；否则 HTML 解析器，且**所有 HTML 标签允许自闭合**（`<a/>` 立即闭合）。

### 5.2 一段的结构

`@CSS:` 前缀（不敏感，AnalyzeByJSoup.kt:509-517）：剥去 5 字符并 trim，进入 CSS 模式：每个 `&&/||/%%` 子项按**最后一个** `@` 切为 `CSS选择器@末段关键字`（:90-95）。
非 CSS 模式：先 `trim()` 掉前导 `@`/空白，再按 `@` 切分（括号/引号感知）；前 n−1 项是逐级元素选择（对上一级每个元素求值后拉平），最后一项是末段关键字（:196-218）。JSoup `getStringList("")` 在处理前直接返回 `[]`（AnalyzeByJSoup.kt:72）；非空原始规则经前缀处理后为空，如 `getStringList("@CSS:")`，才返回 `[element.data()]`（AnalyzeByJSoup.kt:75-79, 509-517）。

### 5.3 末段关键字（AnalyzeByJSoup.kt:224-275，区分大小写）

| 关键字 | 语义 | 空值 |
| --- | --- | --- |
| `text` | 每个元素 `text()`（合并后代文本） | 空串跳过 |
| `textNodes` | 每个元素的直接文本节点各自 trim、去空，用 `\n` 连接为一项 | 无文本节点跳过 |
| `ownText` | 每个元素自身文本 | 空串跳过 |
| `html` | **先从这些元素中删除 `script`/`style`（修改 DOM）**，再取全部 outerHtml 为一项 | 空串跳过 |
| `all` | 全部 outerHtml 为一项，不删 script | 不跳过 |
| 其他 | 视为属性名 `attr(名)`（jsoup 语义，含 `abs:` 前缀） | 空白跳过，**去重** |

### 5.4 元素选择器（`ElementsSingle`，AnalyzeByJSoup.kt:298-317）

先由 `findIndexSet` 从规则**尾部逆向**剥出索引部分，余下 `beforeRule` 按 `.` 切首词：

| 首词 | 选取 |
| --- | --- |
| 空 | 直接子元素 |
| `children` | 直接子元素 |
| `class` | `getElementsByClass(第二词)` |
| `tag` | `getElementsByTag(第二词)`（多余词被忽略：`tag.div.p` 等价 `tag.div`） |
| `id` | id 等于第二词的元素 |
| `text` | 自身文本包含第二词的元素 |
| 其他 | 整个 `beforeRule` 作 jsoup CSS 选择器 |

### 5.5 索引语法（AnalyzeByJSoup.kt:401-505 解析；319-397 应用）

**旧式** `X.i`、`X!i`、`X.i:j:k`：`:` 分隔的是**多个独立索引**而非区间；`.` 选取、`!` 排除；负数从尾计（−1 为末项）；越界索引丢弃；重复去重、保持书写顺序。数字为空（如 `tag.div.`）→ 抛数字格式异常。

**新式** `X[a, b:c, d:e:f]`、`X[!…]`：
- 单索引同上。区间 `start:end:step`：start 省略 = 0，end 省略 = len−1；负值加 len；两端同侧越界则整个区间丢弃；单侧越界钳到 0 / len−1；`start==end` 或 `step>=len` 时只取 start。
- step：正数原样；零且 `len>0` → `len`；负数且 `−step < len` → `step+len`；否则 1（AnalyzeByJSoup.kt:361-362）。`end>start` 升序、否则**降序**展开，`[-1:0]` 即整体反转。
- `[!` 表示排除。`]` 结尾但内部出现非数字/非 `,:-` 字符 → 不当索引，整段作 CSS 选择器（如 `a[href]`）。
- 应用：排除 → 从结果列表按索引删除（不改 DOM）；选取 → 按索引集合顺序取；无索引 → 全部。

示例（`<ul><li>0</li><li>1</li><li>2</li><li>3</li></ul>`，len=4）：

| 规则 | 选中 li 的文本 |
| --- | --- |
| `tag.li.0:2` | `0`,`2`（独立索引） |
| `tag.li.-1` | `3` |
| `tag.li!0` | `1`,`2`,`3` |
| `tag.li[1:]` | `1`,`2`,`3` |
| `tag.li[-1:0]` | `3`,`2`,`1`,`0` |
| `tag.li[0:3:2]` | `0`,`2` |
| `tag.li[0:3:0]` | `0`（步长为 len=4，AnalyzeByJSoup.kt:362-365） |
| `tag.li[!0,-1]` | `1`,`2` |
| `tag.li[5]` | 空 |

## 6. `&&` / `||` / `%%` 合并语义

各层实现相同骨架（JSoup: AnalyzeByJSoup.kt:83-119、134-190；XPath: AnalyzeByXPath.kt:57-89、95-130；JsonPath: AnalyzeByJSonPath.kt:77-125、135-172）：

1. 用 `RuleAnalyzer.splitRule("&&","||","%%")` 切分（JsonPath 用代码平衡组）；只有 1 项则直接求值。
2. 逐项求值：字符串列表入口排除空列表（AnalyzeByJSoup.kt:100-103；AnalyzeByXPath.kt:107-112；AnalyzeByJSonPath.kt:102-107）；JSoup 元素入口保留空列表（AnalyzeByJSoup.kt:141, 169），XPath / JsonPath 元素或对象列表入口仍排除空列表（AnalyzeByXPath.kt:66-71；AnalyzeByJSonPath.kt:149-154）。`elementsType=="||"` 时遇到首个非空结果即停止（短路）。
3. `%%`：以**第一个保留的结果列表长度**为轮数，第 i 轮依次取每个结果的第 i 项（不足者跳过）→ 更长的后续列表被截断。字符串列表入口取首个非空列表长度（AnalyzeByJSoup.kt:100-113；AnalyzeByXPath.kt:107-122；AnalyzeByJSonPath.kt:102-117）；JSoup 元素入口取首个列表长度，首项为空即返回空列表（AnalyzeByJSoup.kt:175-183）；XPath / JsonPath 元素或对象列表入口取首个非空列表长度（AnalyzeByXPath.kt:66-81；AnalyzeByJSonPath.kt:149-164）。`&&`：顺序拼接。
4. 不去重（末段属性名的去重是 §5.3 的独立行为）。

`getString` 类入口在 XPath / JsonPath 层只切 `&&`、`||`（AnalyzeByXPath.kt:135；AnalyzeByJSonPath.kt:38），多项结果用 `\n` 连接；JSoup `getString` 是 `getStringList` 的 `\n` 连接（AnalyzeByJSoup.kt:44-56），单项直接返回，空 → null。

示例：内容 `<a>x</a><a>y</a><b>1</b>`，规则 `tag.a@text%%tag.b@text` → `["x","1","y"]`；`tag.b@text%%tag.a@text` → `["1","x"]`（`y` 被截断）；`tag.c@text||tag.b@text` → `["1"]`；`tag.a@text&&tag.b@text` → `["x","y","1"]`。
内容 `<b>1</b>`，JSoup 元素规则 `tag.a%%tag.b` → `[]`（AnalyzeByJSoup.kt:169, 177-183）；字符串规则 `tag.a@text%%tag.b@text` → `["1"]`（AnalyzeByJSoup.kt:100-113）。

## 7. `##` 替换与 `$n` 回填

### 7.1 拆分（AnalyzeRule.kt:823-834）

模板回填后的规则按 `##` 全部切开：`[0]`=trim 后的规则，`[1]`=匹配正则，`[2]`=替换串（缺省 `""`），**段数 > 3**（即 `##a##b###`）→ 「只取首个匹配」模式。

### 7.2 执行（AnalyzeRule.kt:544-568）

| 形式 | 正则合法 | 语义 |
| --- | --- | --- |
| `##m##r` | 是 | 全部替换 `result.replace(regex, r)`；`r` 支持 `$1` 组引用；替换过程异常 → 退化为纯文本替换 |
| `##m##r` | 否 | 纯文本替换（把子串 `m` 换成 `r`） |
| `##m##r###` | 是 | 找首个匹配；有 → 仅对**该匹配子串**做一次替换并返回它（等价「提取并改写」）；无 → `""` |
| `##m##r###` | 否 | 返回 `r` 字面量 |

正则编译缓存上限 16 条（MapExtensions.kt:21-32：满后仍计算但不缓存）。

示例：结果 `第12章 序`，规则 `…##第(\d+)章.*##$1###` → `12`；规则 `…##\s+##` → `第12章序`；规则 `…##章##回` → `第12回 序`。

### 7.3 `$n` 回填（AnalyzeRule.kt:776-820）

参数逆序拼接（结果即正序）：
- 类型 n ≥ 1：当前结果是列表且 `size > n` → 插入第 n 项（为 null 则不插）；列表过短 → **什么都不插**；当前结果不是列表 → 插入字面 `$n`。
- 类型 JS（`{{…}}`）：若内文以 `@`、`$.`、`$[`、`//` 开头 → 视为规则，对**整个内容**（非当前链式结果）用 `getString` 求值（AnalyzeRule.kt:795-799, 837-842）；否则作为 JS 求值：null → 不插；字符串原样；整数值的浮点 → 无小数格式；其他 → toString。
- 类型 GET（`@get:{key}`）→ `get(key)`。
- 类型 0 → 字面文本（含 `$0`）。

## 8. `{{ }}` 内插与 `@get` / `@put` 变量作用域

### 8.1 写入（AnalyzeRule.kt:856-865；RuleDataInterface.kt:7-28）

`put(key, value)` 依次找第一个存在的容器：章节 → 书 → ruleData → 书源。前三者存于各自的 `variableMap`（值长度 ≥ 10000 转入「大变量」存储；null 删除），书源级存于全局缓存键 `v_{源key}_{key}`（BaseSource.kt:359-362），跨会话持久。键 `bookName`/`title` 在对应实体存在时会被 `get` 的特殊分支遮蔽（AnalyzeRule.kt:878-884，见下）；写入这些键会记警告。
`AnalyzeUrl.put` 只写章节 → ruleData，**不落书源**（AnalyzeUrl.kt:426-433）。

### 8.2 读取（AnalyzeRule.kt:875-893；AnalyzeUrl.kt:435-449）

顺序：本地绑定（`setLocal`）→ `bookName`=书名 / `title`=章节名 → 章节变量 → 书变量 → ruleData 变量 → 书源变量 → `""`。本地绑定命中即返回，含空串（AnalyzeRule.kt:876）；特殊键仅在对应书 / 章节实体存在时直接返回其名称，含空串，并遮蔽后续宿主变量（AnalyzeRule.kt:878-884）。仅后面的章节、书、ruleData、书源变量查找链将空串视为不存在继续向下找（AnalyzeRule.kt:886-890）。AnalyzeUrl 的顺序：`extraParams` → bookName/title → 章节 → ruleData → `""`；`extraParams` 命中即返回，含空串（AnalyzeUrl.kt:436），特殊键仅在 `ruleData` 为 Book / 章节存在时直接返回名称，含空串（AnalyzeUrl.kt:438-444），仅后面的章节、ruleData 变量查找链过滤空串（AnalyzeUrl.kt:446-448）。

### 8.3 生命周期

- `@put` 在**每次**求值该段时重新执行（AnalyzeRule.kt:507-511），值为子规则对整个内容 `getString` 的结果。
- `@get`/`{{}}` 在 `makeUpRule` 时展开，同样每次求值重算；段对象按规则串缓存于解析器实例（AnalyzeRule.kt:583-588）。
- 变量随宿主实体（章节 / 书 / 书源）持久化；`RuleData` 仅存活于一次解析会话。

示例：规则 `@put:{"n":"tag.h1@text"}tag.p@text` 先把 `<h1>` 文本存入 `n`，再返回 `<p>` 文本；后续字段 `@get:{n}` 返回该值（模式变 Regex，直接输出模板）。

## 9. JS 上下文注入变量

### 9.1 `AnalyzeRule.evalJS`（AnalyzeRule.kt:896-936）

| 名称 | 类型 | 何时存在 |
| --- | --- | --- |
| `java` | 解析器对象（含全部 JsExtensions 扩展函数、`put/get/ajax` 等） | 总是 |
| `cookie` / `cache` | Cookie 存储 / 缓存管理器 | 总是 |
| `source` / `book` / `chapter` / `rssArticle` | 书源 / 书 / 章节 / RSS 文章，可为 null | 总是（值可空） |
| `result` | 上一段结果（首段为内容） | 总是 |
| `baseUrl` / `src` / `nextChapterUrl` / `title` / `chapters` / `fromBookInfo` | 基址 / 原始内容 / 下一章地址 / 章节名 / 批量章节列表 / 布尔 | 总是（值可空） |
| `paraIndex` / `paraData` / `page` | 字符串（`page` 可转整数则为整数） | 仅当通过 `setLocal` 设置 |

脚本编译缓存 16 条（:938-942）；作用域优先级：书源共享作用域 → 弱引用顶层 → 加密共享作用域 → 新建（:917-933）。

### 9.2 `AnalyzeUrl.evalJS`（AnalyzeUrl.kt:395-424）

`java`, `baseUrl`, `cookie`, `cache`, `page`(整数或 null), `key`, `speakText`, `speakSpeed`, `book`, `source`, `result`, `infoMap`，以及 `extraParams` 的每个键（`page` 键会尝试转整数）。

### 9.3 调用点（`result` 的含义）

| 调用点 | `result` | 来源 |
| --- | --- | --- |
| 规则段 Js / `{{}}` 非规则内文 | 上一段结果 | AnalyzeRule.kt:349, 801 |
| WebJs 段 | 上一段结果的 JSON 序列化，交给 WebView | AnalyzeRule.kt:182-199 |
| URL `<js>`/`@js:` | 此前累积的 URL 文本 | AnalyzeUrl.kt:200 |
| URL `{{}}` | 无（null） | AnalyzeUrl.kt:221-228 |
| 选项 `js` | 已绝对化的 url | AnalyzeUrl.kt:292-296 |
| 选项 `bodyJs` | 响应体 | AnalyzeUrl.kt:548-551 |

## 10. `AnalyzeUrl` 的 URL 语法

处理顺序（AnalyzeUrl.kt:175-183）：① `analyzeJs` → ② `replaceKeyPageJs` → ③ `analyzeUrl`。构造时传入的 `baseUrl` 先被截掉自身的 `,{…}` 选项（:137-138）。

### 10.1 `<js>` / `@js:` 段（AnalyzeUrl.kt:188-211）

按 `JS_PATTERN` 切分；初始 `result` = 整个规则串。文本段：`result = 文本.replace("@result", result)`；JS 段：`result = evalJS(js, result).toString()`。无 JS 时串不变。

### 10.2 `{{ }}` 内插（AnalyzeUrl.kt:216-230）

仅当同时含 `{{` 和 `}}` 时用 `innerRule("{{","}}")` 逐个作为 JS 求值：null → `""`；整数值浮点 → 无小数；其他 toString。内文可使用 §9.2 全部变量，`{{key}}`、`{{page}}` 就是变量引用，**不存在 `searchPage` 变量**。

### 10.3 `<a,b,c>` 分页占位（AnalyzeUrl.kt:232-242）

仅在传入 `page` 时处理：`<(.*?)>` 每个匹配按 `,` 切分，取第 `page` 项（1 起）并 trim；`page ≥ 项数` 时取最后一项。示例 `https://x/s?p=<,2,3>`：page 1 → `https://x/s?p=`；page 2 → `…p=2`；page 9 → `…p=3`。

### 10.4 `,{json}` 选项与 URL 拆分（AnalyzeUrl.kt:248-317, 817）

`paramPattern = \s*,\s*(?=\{)`：首个匹配前为 URL（相对 `baseUrl` 绝对化，NetworkUtils.kt:161-187），其后整段为选项 JSON：先严格解析，失败再宽松解析并记日志（:259-265）。
POST 时若 body 非 JSON、非 XML 且未设 `Content-Type` → 按表单 `k=v&k=v` 编码（:303-307）；否则 GET/HEAD 把 `?` 后查询串编码（:309-315）。编码规则（:333-389）：`charset` 空 → UTF-8 且已编码的值不再编码；`"escape"` → JS escape 风格；其他 → 指定字符集；查询串若已整体编码则原样。

### 10.5 选项表（`UrlOption`，AnalyzeUrl.kt:829-885；16 个字段 + 1 个别名键 = 17 个可写键）

| 键 | 类型 | 默认 | 语义 | 来源 |
| --- | --- | --- | --- | --- |
| `method` | 字符串 | GET | 大写后 `POST`/`HEAD`，其余 GET | :267-273 |
| `charset` | 字符串 | UTF-8 | 参数编码字符集，`escape` 特殊 | :281, 333-339 |
| `headers` | 对象或 JSON 字符串 | 无 | 合并进请求头（值 toString） | :274-276, 945-951 |
| `body` | 字符串 / 对象 / 数组 | 无 | 对象、数组序列化回 JSON 字符串 | :277-279, 953-966 |
| `origin` | 字符串 | 无 | **解析但本类未使用** | :837, 902-908 |
| `retry` | 整数 | 0 | 重试次数 | :282, 914-916 |
| `type` | 字符串 | 无 | 非空时视为二进制资源：文本响应返回字节的十六进制 | :280, 461-463 |
| `webView` | 任意 | false | `null/""/false/"false"` 为假，**其余（含 `"0"`）为真** | :283, 926-931 |
| `webJs` | 字符串 | 无 | WebView 内执行的 JS | :284 |
| `timeout` | 整数或数字串 | 无 | 读超时毫秒，范围 1..2³¹−1；设置后 call 超时 = max(60000, min(2147483647, 2×timeout)) | :286-289; AnalyzeUrlNetworkOptions.kt:12-23, 77-84 |
| `followRedirects` | 布尔/0/1/字符串 | 无（跟随） | `true/1/"true"/"1"` 真，`false/0/"false"/"0"` 假，其他忽略 | :290; NetworkOptions.kt:25-40 |
| `dnsIp`（别名 `resolveIp`） | 字符串 | 无 | 逗号分隔 IPv4/IPv6 字面量，仅对目标主机生效；与 proxy 同时设置 → 抛错 | :865-866, 291; NetworkOptions.kt:42-70 |
| `js` | 字符串 | 无 | 选项解析后对 url 执行，返回值替换 url | :292-296 |
| `bodyJs` | 字符串 | 无 | 响应后对 body 执行，返回值替换 body | :285, 548-551 |
| `serverID` | 长整数 | 无 | 透传的服务器 id | :297 |
| `webViewDelayTime` | 长整数 | 0 | WebView 加载后等待毫秒，负数取 0 | :298 |

其他：`proxy` 来自书源请求头而非选项（:143-146）；Cookie 由域名级存储合并进 `Cookie` 头（:752-774）；`data:` URL 直接 base64 解码（:683-694）；`CustomUrl` 用同一 `paramPattern` 拆 URL 与属性表并以 `,` 重新拼接（CustomUrl.kt:12-23, 42-47）。

## 11. 已知怪癖与历史兼容行为

| # | 行为 | 来源 |
| --- | --- | --- |
| 1 | HTML 解析器让所有 HTML 标签可自闭合（旧 jsoup 兼容 `<a/>`） | SourceHtmlParser.kt:9-16 |
| 2 | JS 源码中的 `let`/`const` 改写不在本目录，位于 rhino 模块 `normalizeLegacySource` | modules/rhino/src/main/java/com/script/rhino/RhinoContext.kt:143-152 |
| 3 | `:` 开头的列表规则把实例 `isRegex` 置真且不复位，后续所有规则基模式变 Regex | AnalyzeRule.kt:599-605 |
| 4 | `{{}}`/`@get` 出现在 `##` 之前会把整段变成字符串模板（Regex 模式），选择器不再执行 | AnalyzeRule.kt:706-710 |
| 5 | `$0` 不回填，按字面输出 | AnalyzeRule.kt:761, 783 |
| 6 | 列表入口不做模板回填与 `##` 拆分 | AnalyzeRule.kt:459-476 |
| 7 | `{{@css:…}}` 等内嵌规则对整个内容求值，而非当前链式结果 | AnalyzeRule.kt:795-799 |
| 8 | `html` 关键字删除元素内 `script`/`style`，影响同一 DOM 上的后续规则 | AnalyzeByJSoup.kt:255-258 |
| 9 | JSoup 的 `%%`：字符串入口以首个非空列表长度截断；元素入口以首个列表长度截断，首项为空即返回空列表 | AnalyzeByJSoup.kt:100-113, 141, 169, 177-183 |
| 10 | 旧式 `a:b` 是独立索引不是区间；`tag.div.` 抛异常；全 `@`/空白规则越界抛异常 | AnalyzeByJSoup.kt:477-501；RuleAnalyzer.kt:15-22 |
| 11 | 同一层只承认首个出现的组合符 | RuleAnalyzer.kt:191, 208 |
| 12 | `<js>` 块内若含 `@webjs:` 会被再次切出一个 WebJs 段 | AnalyzeRule.kt:618-628 |
| 13 | HTML 反转义只在 getString 做，getStringList 不做 | AnalyzeRule.kt:367-372 |
| 14 | XPath 输入字符串以 `</td>` 结尾补 `<tr>`，以 `</tr>`/`</tbody>` 结尾补 `<table>` | AnalyzeByXPath.kt:27-41 |
| 15 | JsonPath 用默认配置（非全局 `SUPPRESS_EXCEPTIONS` 配置），读取异常被捕获：getString 返回 `""`、getStringList 返回空、getList 返回空、getObject 直接抛 | AnalyzeByJSonPath.kt:18-27, 47-56, 128-144 |
| 16 | JsonPath getStringList 若内嵌 `{$.}` 替换成功，结果只有一项 | AnalyzeByJSonPath.kt:82-96 |
| 17 | `webView:"0"` 为真；`origin` 无效果；`searchPage` 不是变量 | AnalyzeUrl.kt:926-931, 837 |
| 18 | JS 对象/Gson 映射内容只取第一段规则 | AnalyzeRule.kt:221-247, 325-340 |
| 19 | `@put` 的 JSON 值不能含 `}`；`@put`/`@get` 键名 `bookName`、`title` 在对应实体存在时被内置值遮蔽 | AnalyzeRule.kt:1027, 856-859, 878-886 |

### 未确定，需实测

| 条目 | 说明 |
| --- | --- |
| U1 | Jayway JsonPath 对不以 `$` 开头的路径（如 `data.list`）是否自动补 `$.`，以及 3.0.0 对缺失路径的默认异常类型 |
| U2 | jsoup 1.23.2 `Element.attr(name)` 对属性名大小写的处理（规则 `@HREF` 是否等价 `@href`） |
| U3 | `Element.data()` 在非 `script/style` 元素上的返回值（决定 JSoup 非空原始规则经前缀处理后为空，如 `getStringList("@CSS:")` 时的输出；原始空串直接返回 `[]`，AnalyzeByJSoup.kt:72-79, 509-517） |
| U4 | Kotlin `String.replace(Regex, replacement)` 对替换串中 `\` 与 `$` 的转义细节需与 Swift 正则替换逐字对齐 |
| U5 | `%.0f` 对 `-0.0`、超大浮点的格式化输出 |
| U6 | `RFC3986` 查询编码器与 `URLEncoder` 表单编码器在空格、`+`、`~` 上的精确输出 |
| U7 | JsoupXpath 扩展函数集合（`text()`、`html()`、`num()`、`allText()` 等）及 `asString()` 的输出格式 |
