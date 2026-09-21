# JSONPath 补全（P9）

规格基线为 Kotlin `2bdd3c58b` 使用的 Jayway JsonPath `3.0.0`。实现复用既有解析器，不增加依赖。

| 输入 | 输出 |
| --- | --- |
| `[9223372036854775808,9223372036854775809]`，`$[?(@ > 9223372036854775808)]` | `9223372036854775809`，不经过 Double 舍入 |
| tags 包含 a/b，`subsetof ['a','b']` | 保留该项及空集合项 |
| `[1,2,3,4]` 的 avg/stddev | `2.5` / `sqrt(1.25)` |
| nums `[1,2,3]`，`append(4).avg()` | `2.5` |
| words `["a",2,"b"]`，`concat("c")` | `abc` |
| `[1,2,3]`，`index(-1)` / `index(-3)` | `3` / 抛错（沿用该版本负索引边界） |

新增 contains/subsetof/anyof/noneof、avg/stddev/size/keys/concat/append/index，函数参数支持字面量、数组、对象和 JSONPath；支持嵌套函数路径及后续链式查询。keys 保留解析时的键顺序。

数值与边界依据 [StandardDeviation.java](https://github.com/json-path/JsonPath/blob/json-path-3.0.0/json-path/src/main/java/com/jayway/jsonpath/internal/function/numeric/StandardDeviation.java)、[AbstractSequenceAggregation.java](https://github.com/json-path/JsonPath/blob/json-path-3.0.0/json-path/src/main/java/com/jayway/jsonpath/internal/function/sequence/AbstractSequenceAggregation.java)；参数与数组操作依据同 tag 的 function 目录。append 的当前 Swift 值语义返回扩展后的数组，未修改后续独立查询的输入文档。

验证：新增 4 项先红（17 处断言/异常），修复后 Core 727/0、AppCore 318/0、generic iOS 构建通过；原有 13 项 JSONPath 单测与合成语料不回退。日志 .build/round5/p9-json-*.log。
