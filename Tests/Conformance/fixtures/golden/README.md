# Android 规则引擎黄金用例

生成依据为主 checkout 的 `cb664b84d64e9a7ec9e18f1f1edd819786190222`。每个 JSON 文件是一个有已转换断言的测试类的用例数组。期望值仅复制显式断言，不运行被测实现生成答案。

## Schema

没有可转换断言的测试类不生成文件。

键顺序为 `id, source, kind, input, expect, notes, requiresAndroid`。source 的 line 为断言起始行（从 1 开始）；file 相对 Android 仓库根。循环参数展开为独立用例，固定重复轮次用 variables.repeat 表示。

```json
{
  "type": "array",
  "items": {
    "type": "object",
    "required": [
      "id",
      "source",
      "kind",
      "input",
      "expect",
      "notes",
      "requiresAndroid"
    ],
    "additionalProperties": false,
    "properties": {
      "id": {
        "type": "string",
        "pattern": "^golden-.+-[0-9]+$"
      },
      "source": {
        "type": "object",
        "required": [
          "file",
          "method",
          "line",
          "commit"
        ],
        "properties": {
          "file": {
            "type": "string"
          },
          "method": {
            "type": "string"
          },
          "line": {
            "type": "integer",
            "minimum": 1
          },
          "commit": {
            "const": "cb664b84d"
          }
        }
      },
      "kind": {
        "enum": [
          "jsoup-default",
          "jsoup-css",
          "xpath",
          "jsonpath",
          "regex",
          "js",
          "url-options",
          "replace",
          "format"
        ]
      },
      "input": {
        "type": "object",
        "required": [
          "document",
          "documentType",
          "rule"
        ],
        "properties": {
          "document": {
            "type": [
              "string",
              "null"
            ]
          },
          "documentType": {
            "enum": [
              "html",
              "json",
              "text"
            ]
          },
          "rule": {
            "type": "string"
          },
          "baseUrl": {
            "type": "string"
          },
          "variables": {
            "type": "object"
          }
        }
      },
      "expect": {
        "oneOf": [
          {
            "type": "object",
            "required": [
              "type",
              "value"
            ],
            "properties": {
              "type": {
                "const": "string"
              },
              "value": {
                "type": "string"
              }
            }
          },
          {
            "type": "object",
            "required": [
              "type",
              "value"
            ],
            "properties": {
              "type": {
                "const": "stringList"
              },
              "value": {
                "type": "array",
                "items": {
                  "type": "string"
                }
              }
            }
          },
          {
            "type": "object",
            "required": [
              "type",
              "value"
            ],
            "properties": {
              "type": {
                "const": "error"
              },
              "value": {
                "type": "string"
              }
            }
          }
        ]
      },
      "notes": {
        "type": "string"
      },
      "requiresAndroid": {
        "type": "boolean"
      }
    }
  }
}
```

`document: null` 仅用于原测试的 null 输入，不能换成空串。error.value 为原 assertThrows 指定的异常类名，跨语言 runner 需映射等价异常类别，不匹配或臆造消息。数字、布尔、null 期望值不强制转字符串；空数字列表也不能冒充 stringList。

## 执行约定

variables 是 runner 配置，不自动全部注入 JavaScript。operation 指明原入口；JS bindings 注入 globals，bindingTypes 保留 JVM 宿主对象的原类型契约，locals 通过 setLocal 设置。getElements 的 projection=id 表示逐项读元素 id；beforeEach 在每轮断言前顺序执行，repeat 次共用一个解析器。UrlOption.setters 按键顺序调用；fromJson 从 document 反序列化，rule 为读取的 getter。parseDnsIpAddresses 的 projection=[0].hostAddress 保留原断言投影。replace 的 rule 为 pattern，其他字段是原 ReplaceRule 配置，入口为 ReplacePreview.apply。format 的 rule 为 format 或 formatIntro。

requiresAndroid 为原入口的依赖标记，不表示已运行 Android。包含 Android 宿主或网络配置类的用例保守标 true；无 Android 依赖但依赖 JVM 桥接的条目在 notes 单列。未运行 Kotlin 或 Swift，本目录只验证数据与来源。

## 未转换

| 测试类 | Kotlin 来源（相对 Android 仓库根） | 未转换原因 |
| --- | --- | --- |
| AnalyzeRuleElementsNormalizationTest | `app/src/test/java/io/legado/app/model/analyzeRule/AnalyzeRuleElementsNormalizationTest.kt` | 需扩展 null / 数字列表类型。 | |
| AnalyzeUrlLoginHeaderContractTest | `app/src/test/java/io/legado/app/model/analyzeRule/AnalyzeUrlLoginHeaderContractTest.kt` | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 | |
| BookSourceImportTest | `app/src/test/java/io/legado/app/ui/association/BookSourceImportTest.kt` | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 | |
| BundlePayloadContractTest | `app/src/test/java/io/legado/app/BundlePayloadContractTest.kt` | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 | |
| CryptoJsCompatibilityTest | `app/src/test/java/io/legado/app/model/CryptoJsCompatibilityTest.kt` | 需表达原类型、复合步骤或宿主状态；不推导期望值。 | |
| ImportBookSourceStateTest | `app/src/test/java/io/legado/app/ui/association/ImportBookSourceStateTest.kt` | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 | |
| ManagePopupActionMigrationTest | `app/src/test/java/io/legado/app/ui/menu/ManagePopupActionMigrationTest.kt` | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 | |
| ManualReplaceRuleContractTest | `app/src/test/java/io/legado/app/model/ManualReplaceRuleContractTest.kt` | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 | |
| ManualSourceReplacementTest | `app/src/test/java/io/legado/app/ui/association/ManualSourceReplacementTest.kt` | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 | |
| NoGroupDaoFilterContractTest | `app/src/test/java/io/legado/app/data/dao/NoGroupDaoFilterContractTest.kt` | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 | |
| PullBookmarkGestureTest | `app/src/test/java/io/legado/app/ui/book/read/page/PullBookmarkGestureTest.kt` | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 | |
| ReadBookHighlightIsolationTest | `app/src/test/java/io/legado/app/model/ReadBookHighlightIsolationTest.kt` | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 | |
| ReplacePreviewPersistenceContractTest | `app/src/test/java/io/legado/app/ui/replace/edit/ReplacePreviewPersistenceContractTest.kt` | 需表达原类型、复合步骤或宿主状态；不推导期望值。 | |
| ReplaceRuleDaoGroupFilterContractTest | `app/src/test/java/io/legado/app/data/dao/ReplaceRuleDaoGroupFilterContractTest.kt` | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 | |
| ReplaceRuleImportComparisonTest | `app/src/test/java/io/legado/app/ui/association/ReplaceRuleImportComparisonTest.kt` | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 | |
| ReplaceRuleViewModelGroupContractTest | `app/src/test/java/io/legado/app/ui/replace/ReplaceRuleViewModelGroupContractTest.kt` | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 | |
| ReviewRuleParserFallbackTest | `app/src/test/java/io/legado/app/model/analyzeRule/ReviewRuleParserFallbackTest.kt` | 需表达原类型、复合步骤或宿主状态；不推导期望值。 | |
| RssSourceImportTest | `app/src/test/java/io/legado/app/ui/association/RssSourceImportTest.kt` | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 | |
| RuntimeConcurrencyTest | `app/src/test/java/io/legado/app/RuntimeConcurrencyTest.kt` | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 | |
| SourceCompatibilityTest | `app/src/test/java/io/legado/app/SourceCompatibilityTest.kt` | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 | |
| SourceGroupOrderTest | `app/src/test/java/io/legado/app/data/entities/SourceGroupOrderTest.kt` | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 | |
| TocUpdateRequestsTest | `app/src/test/java/io/legado/app/ui/main/TocUpdateRequestsTest.kt` | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 | |
| TxtTocRuleFilterTest | `app/src/test/java/io/legado/app/ui/book/toc/rule/TxtTocRuleFilterTest.kt` | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 | |
| model.ReplacePreviewTest | `app/src/test/java/io/legado/app/model/ReplacePreviewTest.kt` | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 | |

源码 contains/顺序检查、UI 手势、导入比较、DAO 筛选、并发与缓存生命周期等不属于单文档规则输入输出；这些命中项仅保留上表的来源、原因及下面的方法级清单，不生成 JSON 文件。ReviewRuleParser 的实体、日志、计数、分页与复合规则不能删掉中间处理后冒充单条 JSONPath/regex 测试，因此尚未转换。CryptoJsCompatibilityTest 涉及共享 scope、库资产和宿主初始化，尚未定义其跨语言 setup 协议。未新增 XPath、JSONPath 或 regex 期望值来填补覆盖面。

## 待人工确认

下表穷举检索命中及入口六文件中未转换的断言位置（相对仓库根）；其中还包含超出规则引擎范围的检查。需决定是否扩展结果类型或 setup/实体/日志协议。JsTest 中 expected/actual 反向的断言暂不转换，避免擅自倒置；HtmlFormatter 的 legacyFormat 动态期望不执行求值；DOM 文档快照和节点身份不推导为字符串。

| Kotlin 文件 | 方法 | 未转换断言行号 | 原因 / 所需决定 |
| --- | --- | --- | --- |
| app/src/test/java/io/legado/app/model/analyzeRule/AnalyzeRuleElementsNormalizationTest.kt | javascriptArrayResultsBecomeUsableElementLists | 12 | 需扩展 null / 数字列表类型。 |
| app/src/test/java/io/legado/app/model/analyzeRule/AnalyzeByJSoupDomTest.kt | self closing links preserve legacy direct text nodes | 17 | 需表达原 DOM 快照、节点身份、根元素选择或清理流水线。 |
| app/src/test/java/io/legado/app/model/analyzeRule/AnalyzeByJSoupDomTest.kt | reading a book name does not replace its link with the author link | 44, 45, 46, 47 | 需表达原 DOM 快照、节点身份、根元素选择或清理流水线。 |
| app/src/test/java/io/legado/app/model/analyzeRule/AnalyzeByJSoupDomTest.kt | reading a forum title leaves its thread link available | 66, 67, 68, 69 | 需表达原 DOM 快照、节点身份、根元素选择或清理流水线。 |
| app/src/test/java/io/legado/app/model/analyzeRule/AnalyzeByJSoupDomTest.kt | chained element selection preserves the original document and parents | 82, 83, 84, 85 | 需表达原 DOM 快照、节点身份、根元素选择或清理流水线。 |
| app/src/test/java/io/legado/app/model/analyzeRule/AnalyzeByJSoupDomTest.kt | excluding indexes filters results without removing document nodes | 103 | 需表达原 DOM 快照、节点身份、根元素选择或清理流水线。 |
| app/src/test/java/io/legado/app/model/analyzeRule/AnalyzeByJSoupDomTest.kt | positive and negative indexes keep selection order and node identity | 116, 117 | 需表达原 DOM 快照、节点身份、根元素选择或清理流水线。 |
| app/src/test/java/io/legado/app/model/analyzeRule/AnalyzeUrlLoginHeaderContractTest.kt | login headers are restricted to the source site | 12, 13, 14 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/model/analyzeRule/ReviewRuleParserTest.kt | summary configuration requires every lookup rule | 37, 39 | 需表达原类型、复合步骤或宿主状态；不推导期望值。 |
| app/src/test/java/io/legado/app/model/analyzeRule/ReviewRuleParserTest.kt | parses JSON summary returned as a native array | 67, 68, 69 | 需表达原类型、复合步骤或宿主状态；不推导期望值。 |
| app/src/test/java/io/legado/app/model/analyzeRule/ReviewRuleParserTest.kt | parses detail content protocol replies and local next page variables | 126, 127, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 141, 142, 143, 144, 145, 146, 147, 148, 151 | 需表达原类型、复合步骤或宿主状态；不推导期望值。 |
| app/src/test/java/io/legado/app/model/analyzeRule/ReviewRuleParserTest.kt | declarative detail preserves 64-bit numeric ids | 174 | 需表达原类型、复合步骤或宿主状态；不推导期望值。 |
| app/src/test/java/io/legado/app/model/analyzeRule/ReviewRuleParserTest.kt | parses a standalone reply page with reply rules | 214, 215, 216, 217, 218, 219, 220, 221, 222, 223 | 需表达原类型、复合步骤或宿主状态；不推导期望值。 |
| app/src/test/java/io/legado/app/model/analyzeRule/ReviewRuleParserTest.kt | standalone reply rule is not evaluated against detail items | 250, 251, 252 | 需表达原类型、复合步骤或宿主状态；不推导期望值。 |
| app/src/test/java/io/legado/app/model/analyzeRule/ReviewRuleParserTest.kt | standalone reply list failures are retryable errors | 257 | 需表达原类型、复合步骤或宿主状态；不推导期望值。 |
| app/src/test/java/io/legado/app/model/analyzeRule/ReviewRuleParserTest.kt | detail JavaScript keeps grouped roots and replies when optional badges are missing | 350, 352, 353, 354, 355, 356, 358, 359, 360, 361 | 需表达原类型、复合步骤或宿主状态；不推导期望值。 |
| app/src/test/java/io/legado/app/model/analyzeRule/ReviewRuleParserTest.kt | detail JavaScript list fields execute against native objects | 387 | 需表达原类型、复合步骤或宿主状态；不推导期望值。 |
| app/src/test/java/io/legado/app/model/analyzeRule/ReviewRuleParserTest.kt | legacy review rules survive converter round trip and equality checks them | 399, 400, 401, 402 | 需表达原类型、复合步骤或宿主状态；不推导期望值。 |
| app/src/test/java/io/legado/app/model/analyzeRule/ReviewRuleParserTest.kt | url extra parameters preserve info map and only add supplied globals | 439, 458 | 需表达原类型、复合步骤或宿主状态；不推导期望值。 |
| app/src/test/java/io/legado/app/model/analyzeRule/ReviewRuleParserFallbackTest.kt | missing optional JSONPath fields stay empty without error logs | 68, 70, 71, 72, 73, 74, 76 | 需表达原类型、复合步骤或宿主状态；不推导期望值。 |
| app/src/test/java/io/legado/app/model/analyzeRule/ReviewRuleParserFallbackTest.kt | rule failures keep empty fallback and are recorded | 113, 114, 139, 140, 165 | 需表达原类型、复合步骤或宿主状态；不推导期望值。 |
| app/src/test/java/io/legado/app/model/analyzeRule/ReviewRuleParserFallbackTest.kt | summary falls back to list order and ignores unusable counts | 212, 213, 214 | 需表达原类型、复合步骤或宿主状态；不推导期望值。 |
| app/src/test/java/io/legado/app/model/analyzeRule/ReviewRuleParserFallbackTest.kt | missing required count JSONPath is recorded once | 251, 252 | 需表达原类型、复合步骤或宿主状态；不推导期望值。 |
| app/src/test/java/io/legado/app/model/analyzeRule/ReviewRuleParserFallbackTest.kt | missing required detail and reply content JSONPaths are recorded once each | 302, 303, 304, 305 | 需表达原类型、复合步骤或宿主状态；不推导期望值。 |
| app/src/test/java/io/legado/app/model/analyzeRule/ReviewRuleParserFallbackTest.kt | summary accepts a JSON array string returned by JavaScript | 340, 341 | 需表达原类型、复合步骤或宿主状态；不推导期望值。 |
| app/src/test/java/io/legado/app/model/analyzeRule/ReviewRuleParserFallbackTest.kt | summary keeps every regex list match | 373 | 需表达原类型、复合步骤或宿主状态；不推导期望值。 |
| app/src/test/java/io/legado/app/model/analyzeRule/AnalyzeUrlNetworkOptionsTest.kt | cookieDomainFollowsResolvedRequestUrl | 34, 35 | 需表达原类型、复合步骤或宿主状态；不推导期望值。 |
| app/src/test/java/io/legado/app/model/analyzeRule/AnalyzeUrlNetworkOptionsTest.kt | cookieDomainKeepsSyntheticSourceNamespace | 47 | 需表达原类型、复合步骤或宿主状态；不推导期望值。 |
| app/src/test/java/io/legado/app/model/analyzeRule/AnalyzeUrlNetworkOptionsTest.kt | parsesSupportedTimeoutAndRedirectValues | 58, 59, 60, 61, 62, 63, 64, 66, 67, 68, 69, 70, 71 | 需表达原类型、复合步骤或宿主状态；不推导期望值。 |
| app/src/test/java/io/legado/app/model/analyzeRule/AnalyzeUrlNetworkOptionsTest.kt | urlOptionExposesNetworkSettings | 82, 83 | 需表达原类型、复合步骤或宿主状态；不推导期望值。 |
| app/src/test/java/io/legado/app/model/analyzeRule/AnalyzeUrlNetworkOptionsTest.kt | urlOptionDeserializesNetworkSettingsFromJson | 100, 101 | 需表达原类型、复合步骤或宿主状态；不推导期望值。 |
| app/src/test/java/io/legado/app/model/analyzeRule/AnalyzeUrlNetworkOptionsTest.kt | parsesOnlyIpLiterals | 110 | 需表达原类型、复合步骤或宿主状态；不推导期望值。 |
| app/src/test/java/io/legado/app/model/analyzeRule/AnalyzeUrlNetworkOptionsTest.kt | dnsOverrideAppliesOnlyToTargetHost | 130, 131, 132 | 需表达原类型、复合步骤或宿主状态；不推导期望值。 |
| app/src/test/java/io/legado/app/model/analyzeRule/AnalyzeUrlNetworkOptionsTest.kt | disabledRedirectIsReturnedBeforeEnteringWebView | 146, 147, 148 | 需表达原类型、复合步骤或宿主状态；不推导期望值。 |
| app/src/test/java/io/legado/app/model/analyzeRule/AnalyzeUrlNetworkOptionsTest.kt | buildsClientWithBoundedTimeoutsAndRedirectPolicy | 172, 173, 174, 175, 176 | 需表达原类型、复合步骤或宿主状态；不推导期望值。 |
| app/src/test/java/io/legado/app/model/analyzeRule/AnalyzeUrlNetworkOptionsTest.kt | explicitCallTimeoutWinsAndUrlTimeoutCanRemoveInterceptor | 194, 195, 196, 206, 207, 208, 209 | 需表达原类型、复合步骤或宿主状态；不推导期望值。 |
| app/src/test/java/io/legado/app/BundlePayloadContractTest.kt | migrated recycler payloads use platform Bundle | 26 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/utils/HtmlFormatterTest.kt | regular formatter keeps paragraph indentation | 21, 26 | 需表达原类型、复合步骤或宿主状态；不推导期望值。 |
| app/src/test/java/io/legado/app/utils/HtmlFormatterTest.kt | js html formatter resolves relative image urls | 69 | 需表达原类型、复合步骤或宿主状态；不推导期望值。 |
| app/src/test/java/io/legado/app/utils/HtmlFormatterTest.kt | book introduction ingestion uses intro formatting only | 80, 84, 85, 86 | 需表达原类型、复合步骤或宿主状态；不推导期望值。 |
| app/src/test/java/io/legado/app/SourceCompatibilityTest.kt | nativeObjectUsesJsonPathRules | 49, 52, 56, 60 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/SourceCompatibilityTest.kt | escapedJsonPathLikeKeyKeepsDirectAccess | 71 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/SourceCompatibilityTest.kt | jsoupElementsKeepLegacyAttributeAccessFromJavaBindings | 98 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/SourceCompatibilityTest.kt | ordinaryListSubclassesKeepExistingRuntimeMethods | 110 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/SourceCompatibilityTest.kt | jsEncodeOverloadsRemainCallableInsideWithAndEvalScopes | 141 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/SourceCompatibilityTest.kt | rssSourceCryptoMethodsRemainCallableThroughNestedEval | 175 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/SourceCompatibilityTest.kt | jsRequestHeadersAcceptMapsAndJsonStrings | 180, 186, 190, 194, 195, 198 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/SourceCompatibilityTest.kt | httpTtsRecognizesScriptAndFormLoginCapabilities | 205, 206, 207, 208 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/SourceCompatibilityTest.kt | httpTtsSelectionAlwaysOffersAvailableLoginAgain | 213, 214, 215, 220, 221 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/SourceCompatibilityTest.kt | brotliResponseIsTransparentlyDecompressed | 237, 238, 239, 240 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/SourceCompatibilityTest.kt | existingCompressionAndRequestGuardsRemainSupported | 246, 247, 253, 254, 255, 259 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/SourceCompatibilityTest.kt | invalidCompressedResponseClosesOriginalBody | 273, 276 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/RuntimeConcurrencyTest.kt | scriptContextOverloadsAlwaysUseRhinoContext | 33, 34, 35, 40, 41, 42 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/RuntimeConcurrencyTest.kt | suspendedScriptsCanResumeAcrossDispatcherHandoffs | 55, 56 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/RuntimeConcurrencyTest.kt | layoutPageStorageSupportsConcurrentAppendAndIteration | 76, 84, 88 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/data/dao/NoGroupDaoFilterContractTest.kt | no group filters only accept blank values or the complete legacy label | 28, 29, 37, 38, 48, 49, 57, 62, 63 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/data/entities/SourceGroupOrderTest.kt | group updates preserve existing order | 12, 15, 19, 22, 26, 29, 33, 36 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/data/dao/ReplaceRuleDaoGroupFilterContractTest.kt | replace rule group filter matches complete normalized members | 31, 32, 33, 35, 36, 39, 45, 50, 51, 56, 58, 61, 62, 63 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/JsTest.kt | testFor | 71 | 需表达原类型、复合步骤或宿主状态；不推导期望值。 |
| app/src/test/java/io/legado/app/JsTest.kt | testReturnNull | 77 | 需表达原类型、复合步骤或宿主状态；不推导期望值。 |
| app/src/test/java/io/legado/app/JsTest.kt | testReplace | 93 | 需表达原类型、复合步骤或宿主状态；不推导期望值。 |
| app/src/test/java/io/legado/app/JsTest.kt | chapterText | 105 | 需表达原类型、复合步骤或宿主状态；不推导期望值。 |
| app/src/test/java/io/legado/app/JsTest.kt | javaListForEach | 120 | 需表达原类型、复合步骤或宿主状态；不推导期望值。 |
| app/src/test/java/io/legado/app/JsTest.kt | javaListSubclassMethods | 141, 143 | 需表达原类型、复合步骤或宿主状态；不推导期望值。 |
| app/src/test/java/io/legado/app/JsTest.kt | analyzeRuleGetElementsKeepsCollectionMethods | 157 | 需表达原类型、复合步骤或宿主状态；不推导期望值。 |
| app/src/test/java/io/legado/app/JsTest.kt | javaStringInteropBoundary | 173, 174, 175, 176, 177, 178, 179, 181, 182, 183, 195, 196, 201, 202, 203, 204 | 需表达原类型、复合步骤或宿主状态；不推导期望值。 |
| app/src/test/java/io/legado/app/JsTest.kt | indirectEvalDynamicRealm | 222 | 需表达原类型、复合步骤或宿主状态；不推导期望值。 |
| app/src/test/java/io/legado/app/JsTest.kt | typeofString | 234 | 需表达原类型、复合步骤或宿主状态；不推导期望值。 |
| app/src/test/java/io/legado/app/ui/association/ManualSourceReplacementTest.kt | bookManualSelectionUsesRawSourceAndTracksChangesOnly | 22, 23, 25, 27, 28 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/association/ManualSourceReplacementTest.kt | rssManualSelectionKeepsUnselectedCandidateAndEditsItsRawSource | 37, 38, 40, 41 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/association/ManualSourceReplacementTest.kt | invalidReplacementStillIdentifiesTheRuleThatChangedIt | 48, 49, 50, 51, 52, 53 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/association/BookSourceImportTest.kt | parses a single book source object | 27, 29, 30 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/association/BookSourceImportTest.kt | rejects a single object without a usable source url | 43, 46 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/association/BookSourceImportTest.kt | rejects any invalid book source array item | 68, 71 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/association/BookSourceImportTest.kt | preserves valid book source array imports | 86 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/association/BookSourceImportTest.kt | validates source urls wrapper while preserving empty arrays | 97, 109, 115, 117 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/association/BookSourceImportTest.kt | source replacement runs in rule order without changing the original | 152, 153, 154 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/association/BookSourceImportTest.kt | rule manager refreshes every candidate and keeps the edited draft | 184, 187, 197, 200 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/association/BookSourceImportTest.kt | source replacement honors include and exclude scope | 222, 226 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/association/BookSourceImportTest.kt | invalid replaced source remains previewable but cannot be imported | 247, 253, 254, 255 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/association/BookSourceImportTest.kt | replace rule source scope is backward compatible and independent | 263, 272, 273, 274 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/association/RssSourceImportTest.kt | parses a single rss source object | 26, 28, 29 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/association/RssSourceImportTest.kt | single source parser accepts objects and one-item arrays | 41, 42 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/association/RssSourceImportTest.kt | single source parser keeps incomplete objects editable | 49, 50 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/association/RssSourceImportTest.kt | single source parser rejects empty and multi-item arrays | 62, 65 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/association/RssSourceImportTest.kt | rejects a single object without a usable source url | 79, 82 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/association/RssSourceImportTest.kt | preserves rss source array imports | 97, 98 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/association/RssSourceImportTest.kt | rejects any rss source array item without a usable source url | 106, 117 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/association/RssSourceImportTest.kt | rejects a later rss source array item whose url is blank | 122, 133 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/association/RssSourceImportTest.kt | shared source url validator rejects empty and whitespace | 139 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/association/RssSourceImportTest.kt | preserves source urls wrapper imports | 158, 159 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/association/RssSourceImportTest.kt | empty source urls wrapper does not become a single source | 174, 175 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/association/RssSourceImportTest.kt | rejects null empty or blank source urls while keeping empty arrays | 187, 190, 193, 198 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/association/RssSourceImportTest.kt | source replacement runs in rule order without changing the original | 228, 229, 230 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/association/RssSourceImportTest.kt | source replacement honors include and exclude scope | 250, 254 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/association/RssSourceImportTest.kt | invalid replaced source remains previewable but cannot be imported | 275, 276, 277, 278, 279 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/association/RssSourceImportTest.kt | rule manager refreshes all candidates and keeps edited draft | 310, 314 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/association/ImportBookSourceStateTest.kt | replace manager refresh keeps the editable source draft | 14, 18 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/association/ImportBookSourceStateTest.kt | classifies new updated and existing sources | 26, 30, 34, 38 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/association/ImportBookSourceStateTest.kt | default selection follows source status | 49, 50 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/association/ImportBookSourceStateTest.kt | manual selection override survives repeated status changes | 58, 59, 60, 61 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/association/ImportBookSourceStateTest.kt | direct JS source import preserves coroutine cancellation | 69, 73 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/association/ImportBookSourceStateTest.kt | book source import shows icon for empty states and hides it for results | 83, 88, 89, 90, 93, 95, 96, 98, 99, 102 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/association/ImportBookSourceStateTest.kt | import comment rows reset collapsed state when rebound | 116, 120 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/association/ImportBookSourceStateTest.kt | association import status labels use localized resources | 139, 140, 141, 142, 143, 152 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/association/ImportBookSourceStateTest.kt | book source replacement preview is isolated from other import dialogs | 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 176, 177, 178, 179, 180, 183, 186, 187, 194, 195, 196, 199, 208, 209, 210, 211, 212, 213, 214, 215, 216, 219, 220, 221, 222, 223, 224, 228, 229, 230, 231, 232, 233, 234, 239, 242, 245, 248, 251, 254, 257, 258, 259, 260, 261, 262, 263, 264, 265, 266, 273, 274, 275, 276, 281, 282, 283, 284, 285, 286, 287, 288 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/association/ImportBookSourceStateTest.kt | reimport explicitly selects same timestamp source while allowing cancellation | 300, 301 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/association/ReplaceRuleImportComparisonTest.kt | keeps a full query chunk within the parameter limit | 25, 26 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/association/ReplaceRuleImportComparisonTest.kt | splits 901 unique ids and removes duplicate query keys | 39, 40, 41, 42 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/association/ReplaceRuleImportComparisonTest.kt | restores import order with unordered missing and duplicate results | 60, 61, 62, 63, 64 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/association/ReplaceRuleImportComparisonTest.kt | empty imports do not query the database | 76, 77, 78 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/association/ReplaceRuleImportComparisonTest.kt | existing rules stay unselected even when their content differs | 93, 94 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/replace/ReplaceRuleViewModelGroupContractTest.kt | group deletion delegates to exact group update | 19, 20, 21 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/replace/ReplaceRuleViewModelGroupContractTest.kt | batch moves allocate orders outside existing bounds | 29, 30, 31, 32 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/replace/ReplaceRuleViewModelGroupContractTest.kt | selection group actions copy rules and update only group members | 37, 42, 47, 48, 49, 50 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/replace/edit/ReplacePreviewTest.kt | sample input is capped at three hundred characters | 17 | 需表达原类型、复合步骤或宿主状态；不推导期望值。 |
| app/src/test/java/io/legado/app/ui/replace/edit/ReplacePreviewTest.kt | sample limit does not leave a dangling unicode surrogate | 24 | 需表达原类型、复合步骤或宿主状态；不推导期望值。 |
| app/src/test/java/io/legado/app/ui/replace/edit/ReplacePreviewTest.kt | preview reports missing book context for context dependent js | 84 | 需表达原类型、复合步骤或宿主状态；不推导期望值。 |
| app/src/test/java/io/legado/app/ui/replace/edit/ReplacePreviewTest.kt | preview reports missing context for non property book references | 99 | 需表达原类型、复合步骤或宿主状态；不推导期望值。 |
| app/src/test/java/io/legado/app/ui/replace/edit/ReplacePreviewTest.kt | preview stops an infinite js replacement at the rule timeout | 126 | 需表达原类型、复合步骤或宿主状态；不推导期望值。 |
| app/src/test/java/io/legado/app/ui/replace/edit/ReplacePreviewTest.kt | preview stops regex work after the rule deadline | 140, 149 | 需表达原类型、复合步骤或宿主状态；不推导期望值。 |
| app/src/test/java/io/legado/app/ui/main/TocUpdateRequestsTest.kt | book state merge preserves video and sync progress | 41, 42, 43, 44, 45, 49, 50, 51, 52, 53 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/main/TocUpdateRequestsTest.kt | selected update filters local and update-disabled books | 74 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/main/TocUpdateRequestsTest.kt | skip pre-download wins when merged into a running regular update | 85, 87 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/main/TocUpdateRequestsTest.kt | regular update cannot override an existing skip policy | 97 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/main/TocUpdateRequestsTest.kt | selected update refreshes book info when merged before execution | 111, 112 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/main/TocUpdateRequestsTest.kt | late selected update queues a book info refresh | 120, 127, 131, 133, 134 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/main/TocUpdateRequestsTest.kt | closed decision remains running until finally cleanup | 141, 143, 144, 145, 146, 149, 152, 156 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/main/TocUpdateRequestsTest.kt | failure cleanup allows the same book to be queued again | 168, 169, 170 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/main/TocUpdateRequestsTest.kt | cancellation clears queued and running policies | 182, 183, 184 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/main/TocUpdateRequestsTest.kt | management action is wired to the skip pre-download policy | 195, 196, 197, 198, 199, 200, 201, 202 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/main/TocUpdateRequestsTest.kt | book info refresh preserves identity and runs toc pre-update rules | 210, 211, 216, 217, 218, 219, 220, 221, 222, 223, 224, 225, 226, 227, 228, 229, 230, 231, 232 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/main/TocUpdateRequestsTest.kt | worker ownership and shelf callback cleanup remain explicit | 239, 240, 241, 242, 243, 244, 245, 246 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/replace/edit/ReplacePreviewPersistenceContractTest.kt | custom backup embeds preview samples during backup and restore | 32, 33, 34 | 需表达原类型、复合步骤或宿主状态；不推导期望值。 |
| app/src/test/java/io/legado/app/ui/replace/edit/ReplacePreviewPersistenceContractTest.kt | preview sample is optional in replacement rule json | 41, 44, 57 | 需表达原类型、复合步骤或宿主状态；不推导期望值。 |
| app/src/test/java/io/legado/app/ui/book/toc/rule/TxtTocRuleFilterTest.kt | blankKeywordReturnsOriginalList | 18 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/book/toc/rule/TxtTocRuleFilterTest.kt | nameMatchIgnoresCaseAndWhitespace | 23 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/book/toc/rule/TxtTocRuleFilterTest.kt | exampleCanBeSearched | 28 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/book/toc/rule/TxtTocRuleFilterTest.kt | missingExampleDoesNotMatchOrCrash | 33 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/model/CryptoJsCompatibilityTest.kt | supports hashes hmac and base64 | 68 | 需表达原类型、复合步骤或宿主状态；不推导期望值。 |
| app/src/test/java/io/legado/app/model/CryptoJsCompatibilityTest.kt | supports aes with explicit key and iv | 95 | 需表达原类型、复合步骤或宿主状态；不推导期望值。 |
| app/src/test/java/io/legado/app/model/CryptoJsCompatibilityTest.kt | uses secure random for word arrays and passphrase salts | 126 | 需表达原类型、复合步骤或宿主状态；不推导期望值。 |
| app/src/test/java/io/legado/app/model/CryptoJsCompatibilityTest.kt | blank js libraries fall back at all four entry points | 143, 148, 157, 161 | 需表达原类型、复合步骤或宿主状态；不推导期望值。 |
| app/src/test/java/io/legado/app/model/CryptoJsCompatibilityTest.kt | js library receives runtime bindings through explicit top level this | 188, 192 | 需表达原类型、复合步骤或宿主状态；不推导期望值。 |
| app/src/test/java/io/legado/app/model/CryptoJsCompatibilityTest.kt | custom js library preserves explicit globals across entry points | 232, 248, 262, 263, 269, 291, 292, 298, 316, 318, 321 | 需表达原类型、复合步骤或宿主状态；不推导期望值。 |
| app/src/test/java/io/legado/app/model/CryptoJsCompatibilityTest.kt | shared global scopes observe current state without stale snapshots | 338, 341, 342, 353, 354, 355, 356, 375 | 需表达原类型、复合步骤或宿主状态；不推导期望值。 |
| app/src/test/java/io/legado/app/model/CryptoJsCompatibilityTest.kt | clearing shared globals invalidates existing handles | 393 | 需表达原类型、复合步骤或宿主状态；不推导期望值。 |
| app/src/test/java/io/legado/app/model/CryptoJsCompatibilityTest.kt | production state cleanup is source specific and refresh aware | 418, 419, 424, 425 | 需表达原类型、复合步骤或宿主状态；不推导期望值。 |
| app/src/test/java/io/legado/app/model/CryptoJsCompatibilityTest.kt | shared global supports concurrent writes and compound enumeration | 456, 469 | 需表达原类型、复合步骤或宿主状态；不推导期望值。 |
| app/src/test/java/io/legado/app/model/CryptoJsCompatibilityTest.kt | js source config exposes the requested top level runtime | 493, 494 | 需表达原类型、复合步骤或宿主状态；不推导期望值。 |
| app/src/test/java/io/legado/app/model/CryptoJsCompatibilityTest.kt | blank library crypto scopes are isolated by source instance | 510, 518, 522 | 需表达原类型、复合步骤或宿主状态；不推导期望值。 |
| app/src/test/java/io/legado/app/model/CryptoJsCompatibilityTest.kt | custom library scopes include isolated crypto instances | 537, 538, 539, 541, 542, 546, 547 | 需表达原类型、复合步骤或宿主状态；不推导期望值。 |
| app/src/test/java/io/legado/app/model/CryptoJsCompatibilityTest.kt | custom library properties remain deletable after initialization | 556 | 需表达原类型、复合步骤或宿主状态；不推导期望值。 |
| app/src/test/java/io/legado/app/model/CryptoJsCompatibilityTest.kt | same custom library is constructed once under concurrent access | 582, 583 | 需表达原类型、复合步骤或宿主状态；不推导期望值。 |
| app/src/test/java/io/legado/app/model/CryptoJsCompatibilityTest.kt | same owner reuses crypto scope on the same thread | 595 | 需表达原类型、复合步骤或宿主状态；不推导期望值。 |
| app/src/test/java/io/legado/app/model/CryptoJsCompatibilityTest.kt | same owner isolates crypto by thread and remains stable concurrently | 620, 621, 624 | 需表达原类型、复合步骤或宿主状态；不推导期望值。 |
| app/src/test/java/io/legado/app/model/CryptoJsCompatibilityTest.kt | crypto bundle is compiled once across isolated owners | 637 | 需表达原类型、复合步骤或宿主状态；不推导期望值。 |
| app/src/test/java/io/legado/app/model/CryptoJsCompatibilityTest.kt | different owner crypto scopes initialize without a global creation lock | 652 | 需表达原类型、复合步骤或宿主状态；不推导期望值。 |
| app/src/test/java/io/legado/app/model/CryptoJsCompatibilityTest.kt | different custom libraries initialize concurrently | 676, 677, 715 | 需表达原类型、复合步骤或宿主状态；不推导期望值。 |
| app/src/test/java/io/legado/app/model/ManualReplaceRuleContractTest.kt | manual rule ids survive read config serialization | 19, 20, 21 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/model/ManualReplaceRuleContractTest.kt | manual mode keeps candidate and reader contracts separated from global rules | 27, 28, 31, 32, 33, 36, 37, 40, 43, 44, 47, 48, 51 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/model/ManualReplaceRuleContractTest.kt | source changes retain old book read config at the database boundary | 57, 58, 59 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/model/ReplacePreviewTest.kt | preview position follows the source anchor across replacement and title changes | 14 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/model/ReplacePreviewTest.kt | preview position clamps when replacement removes the source anchor | 28 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/model/ReplacePreviewTest.kt | two finger candidate uses strict touch slop boundaries | 42, 43, 44 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/model/ReplacePreviewTest.kt | preview stays isolated from reader state and persistent chapter work | 52, 53, 54, 55, 56, 61, 65, 69 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/model/ReplacePreviewTest.kt | gesture and lifecycle gates discard stale preview results | 75, 76, 77, 78, 79, 80, 81, 82, 83, 86, 105, 106, 107 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/model/ReplacePreviewTest.kt | reader setting is opt in | 124, 125, 129, 136 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/model/ReadBookHighlightIsolationTest.kt | highlight belongs only to the matching current book | 18, 19, 20 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/model/ReadBookHighlightIsolationTest.kt | highlight follows chapter url instead of mutable directory index | 32, 33, 34 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/model/ReadBookHighlightIsolationTest.kt | legacy highlight binds once when chapter metadata matches | 51, 52, 53, 54 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/model/ReadBookHighlightIsolationTest.kt | laid out chapter belongs only to the matching book url | 76, 77, 78 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/model/ReadBookHighlightIsolationTest.kt | automatic matching validates async result ownership before caching | 85, 86, 87, 88, 89, 90, 91, 92, 93, 94 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/model/ReadBookHighlightIsolationTest.kt | completed layouts always trigger automatic matching | 103, 104, 105, 106, 107 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/model/ReadBookHighlightIsolationTest.kt | chapter navigation cancels matching for evicted chapters | 120, 122, 124 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/menu/ManagePopupActionMigrationTest.kt | shared popup adds vertical danger styling without losing existing behavior | 41 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/menu/ManagePopupActionMigrationTest.kt | toolbar overflow uses exact items and keeps native fallbacks | 80, 81, 82 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/menu/ManagePopupActionMigrationTest.kt | base activity and fragments install the toolbar overflow bridge | 98 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/menu/ManagePopupActionMigrationTest.kt | dialog menu actions provide icons for the vertical menu | 139 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/menu/ManagePopupActionMigrationTest.kt | five management adapters use the shared vertical menu | 165, 166 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/menu/ManagePopupActionMigrationTest.kt | management menu labels keep their previous order | 234, 242 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/book/read/page/PullBookmarkGestureTest.kt | bookmark pull distance preserves the old default and accepts overrides | 13, 14, 15, 22, 23, 24, 25 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/book/read/page/PullBookmarkGestureTest.kt | bookmark pull moves the page with bounded resistance and rebounds | 30, 31, 32, 37, 38, 41, 42, 47, 48 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/book/read/page/PullBookmarkGestureTest.kt | bookmark pull exposes an opaque reader background | 57 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/book/read/page/PullBookmarkGestureTest.kt | only downward vertical pulls are consumed | 62, 66, 70, 74 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/book/read/page/PullBookmarkGestureTest.kt | release position decides whether bookmark is toggled | 86, 87, 88, 89, 90, 91 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/book/read/page/PullBookmarkGestureTest.kt | bookmark actions use the metadata-bearing current page | 99, 100, 101, 102 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/book/read/page/PullBookmarkGestureTest.kt | bookmark toggle remains pending until confirmation finishes | 110, 111, 112, 115 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/book/read/page/PullBookmarkGestureTest.kt | bookmark indicator refresh waits for page content update | 124, 126 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/book/read/page/PullBookmarkGestureTest.kt | bookmark indicator follows the animated page in both header modes | 136, 137, 142, 143, 144, 145, 146, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 163, 167, 168, 169, 174, 177, 178, 179, 180, 181, 182, 183, 184, 187, 188, 191, 192, 193, 204, 205, 206, 207 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/book/read/page/PullBookmarkGestureTest.kt | bookmark indicator keeps the existing header line metrics | 214, 215, 216, 217, 222, 223, 224 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/book/read/page/PullBookmarkGestureTest.kt | long press clears pull candidate before selecting text | 232 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |
| app/src/test/java/io/legado/app/ui/book/read/page/PullBookmarkGestureTest.kt | text selection magnifier follows drags and always dismisses | 240, 241, 242, 249, 250, 251, 252, 253, 256, 260, 263, 266, 268, 271, 278, 279, 283, 284, 285 | 源码结构、UI、实体筛选、导入、数据库或并发检查，不是单文档规则输出。 |

## 统计与校验

已转换 42 条；用例 JSON 文件 6 个，另有 README.md；24 个无可转换断言的测试类仅记录在未转换表中。

实际校验使用 `python3` 标准库逐文件 `json.loads`，检查数组、ID 唯一性、键顺序、期望值类型、来源断言行和 2 空格规范，并抽查三条 Kotlin 字符串字面量解码后逐字相等。结果：6 个 JSON 文件，42 条用例，无空数组文件；jsoup-default=11、format=8、replace=8、url-options=7、js=8；requiresAndroid=18。抽查：AnalyzeByJSoupDomTest:23、HtmlFormatterTest:52、ui/replace/edit/ReplacePreviewTest:57。未执行 Kotlin / Swift 测试。

校验命令为本轮执行的 `python3` 标准输入脚本；上文记录实际输出。单文件可用 `python3 -m json.tool <文件路径>` 复核解析。
