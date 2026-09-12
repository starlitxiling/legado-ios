# JS 宿主 API 实现优先级

统计日期：2026-09-12。只读离线静态分析，未执行书源 JS，未请求网络。

## 语料来源

| GitHub 仓库 | 仓库内路径 | commit SHA | 下载时间 UTC | 条数 |
| --- | --- | --- | --- | ---: |
| tickmao/Novel | sources/legado/main/full.json | 42c4fde73b2629f71ff303eee3559ef3b947dcc9 | 2026-09-12T12:55:05Z | 1000 |
| aoaostar/legado | sources/3bb7b751.json | 2d5e3e8491515e38c674f8f65417e686d167df7a | 2026-09-12T12:55:11Z | 2117 |
| aoaostar/legado | sources/b778fe6b.json | 2d5e3e8491515e38c674f8f65417e686d167df7a | 2026-09-12T12:55:21Z | 3907 |
| ZWolken/Light-Novel-Yuedu-Source | old_ver/bookSource_202402181650.json | 907717d38fabbb2bcba85b8cb74699554834a3a0 | 2026-09-12T12:55:24Z | 45 |
| aoaostar/legado | sources/2a1f129b.json | 2d5e3e8491515e38c674f8f65417e686d167df7a | 2026-09-12T12:55:45Z | 1554 |
| aoaostar/legado | sources/4dc410d1.json | 2d5e3e8491515e38c674f8f65417e686d167df7a | 2026-09-12T12:55:46Z | 128 |
| aoaostar/legado | sources/e29e19ee.json | 2d5e3e8491515e38c674f8f65417e686d167df7a | 2026-09-12T12:55:49Z | 939 |
| aoaostar/legado | sources/e3e5d620.json | 2d5e3e8491515e38c674f8f65417e686d167df7a | 2026-09-12T12:55:50Z | 86 |

## 统计口径与总量

原始书源 9776 条，按 bookSourceUrl 去重 4063 个；空键 2 条。相同键各版本特性取并集。
直接调用 java 方法的源为 961 个（23.65%）；Kotlin 方法词表 157 个唯一名。
Kotlin 主 checkout HEAD：`35a485ed37dec7ac4a72b578cf2782e00adbe1a0`。词表来自 JsExtensions.kt、JsEncodeUtils.kt、AnalyzeRule.kt、AnalyzeUrl.kt 与 BaseSource.kt 的直接公开成员方法；排除 private/internal/protected、嵌套类型成员及 companion 扩展函数，不把内部 UrlOption 的方法当成 java 对象成员。

下表以使用该特性的去重源数计数；规则标记为字符串出现率；JS 指标屏蔽字符串、注释及可识别正则。详情见 tools/corpus/README.md。
覆盖率分母仅为使用 java 方法的源，必须完整覆盖该源全部直接方法调用；词表外调用仍阻止覆盖。注入变量未区分局部同名变量。
同源多版本取并集比任选一个版本更保守；语料包含历史、失效或停用源，没有可用性权重，不代表全部生态。

词表由原两文件原始 108 名扩为五文件公开成员 157 名；原两文件筛选公开成员后为 104 名，新增三文件贡献 53 个唯一名。

## 规则模式使用率

| 规则模式 | 书源数 | 使用率 |
| --- | ---: | ---: |
| @css: | 158 | 3.89% |
| XPath | 279 | 6.87% |
| JSONPath | 612 | 15.06% |
| <js> | 1037 | 25.52% |
| @js: | 1353 | 33.30% |
| @webjs: | 0 | 0.00% |
| {{ }} | 3518 | 86.59% |
| ## | 3023 | 74.40% |
| && | 1528 | 37.61% |
| &#124;&#124; | 1104 | 27.17% |
| %% | 11 | 0.27% |
| @get | 344 | 8.47% |
| @put | 373 | 9.18% |

## java 方法优先级

累计覆盖率是频率降序前缀的完整依赖覆盖率，同频按方法名排序。最小集合指该固定顺序的最短前缀，未求任意子集的全局最优解。

| 顺位 | 方法 | 书源数 | 使用率 | 累计完整覆盖源数 | 累计覆盖率 |
| ---: | --- | ---: | ---: | ---: | ---: |
| 1 | ajax | 465 | 11.44% | 159 | 16.55% |
| 2 | put | 287 | 7.06% | 206 | 21.44% |
| 3 | getString | 276 | 6.79% | 256 | 26.64% |
| 4 | get | 269 | 6.62% | 348 | 36.21% |
| 5 | timeFormat | 142 | 3.49% | 419 | 43.60% |
| 6 | log | 123 | 3.03% | 464 | 48.28% |
| 7 | toast | 77 | 1.90% | 500 | 52.03% |
| 8 | md5Encode | 74 | 1.82% | 526 | 54.73% |
| 9 | base64Decode | 71 | 1.75% | 578 | 60.15% |
| 10 | getElements | 71 | 1.75% | 620 | 64.52% |
| 11 | setContent | 50 | 1.23% | 636 | 66.18% |
| 12 | toNumChapter | 48 | 1.18% | 684 | 71.18% |
| 13 | post | 42 | 1.03% | 708 | 73.67% |
| 14 | aesBase64DecodeToString | 38 | 0.94% | 743 | 77.32% |
| 15 | encodeURI | 37 | 0.91% | 755 | 78.56% |
| 16 | getElement | 33 | 0.81% | 772 | 80.33% |
| 17 | longToast | 28 | 0.69% | 777 | 80.85% |
| 18 | startBrowserAwait | 26 | 0.64% | 789 | 82.10% |
| 19 | getStringList | 24 | 0.59% | 804 | 83.66% |
| 20 | base64Encode | 23 | 0.57% | 817 | 85.02% |
| 21 | startBrowser | 21 | 0.52% | 831 | 86.47% |
| 22 | base64DecodeToByteArray | 16 | 0.39% | 844 | 87.83% |
| 23 | t2s | 16 | 0.39% | 856 | 89.07% |
| 24 | createSymmetricCrypto | 15 | 0.37% | 865 | 90.01% |
| 25 | webView | 12 | 0.30% | 874 | 90.95% |
| 26 | head | 11 | 0.27% | 885 | 92.09% |
| 27 | connect | 10 | 0.25% | 894 | 93.03% |
| 28 | getCookie | 10 | 0.25% | 899 | 93.55% |
| 29 | ajaxAll | 9 | 0.22% | 905 | 94.17% |
| 30 | getVerificationCode | 9 | 0.22% | 912 | 94.90% |
| 31 | timeFormatUTC | 9 | 0.22% | 918 | 95.53% |
| 32 | hexDecodeToString | 7 | 0.17% | 924 | 96.15% |
| 33 | refreshTocUrl | 7 | 0.17% | 927 | 96.46% |
| 34 | getWebViewUA | 6 | 0.15% | 930 | 96.77% |
| 35 | randomUUID | 6 | 0.15% | 931 | 96.88% |
| 36 | HMacHex | 5 | 0.12% | 932 | 96.98% |
| 37 | androidId | 4 | 0.10% | 935 | 97.29% |
| 38 | desEncodeToBase64String | 4 | 0.10% | 939 | 97.71% |
| 39 | digestHex | 3 | 0.07% | 941 | 97.92% |
| 40 | queryBase64TTF | 3 | 0.07% | 941 | 97.92% |
| 41 | queryTTF | 3 | 0.07% | 941 | 97.92% |
| 42 | refreshBookUrl（词表外） | 3 | 0.07% | 944 | 98.23% |
| 43 | replaceFont | 3 | 0.07% | 946 | 98.44% |
| 44 | s2t | 3 | 0.07% | 947 | 98.54% |
| 45 | base64Decoder（词表外） | 2 | 0.05% | 949 | 98.75% |
| 46 | getStrResponse | 2 | 0.05% | 949 | 98.75% |
| 47 | getUserAgent | 2 | 0.05% | 950 | 98.86% |
| 48 | md5Encode16 | 2 | 0.05% | 951 | 98.96% |
| 49 | HMacBase64 | 1 | 0.02% | 952 | 99.06% |
| 50 | aesEncodeToBase64String | 1 | 0.02% | 953 | 99.17% |
| 51 | bytesToStr | 1 | 0.02% | 954 | 99.27% |
| 52 | deviceID（词表外） | 1 | 0.02% | 955 | 99.38% |
| 53 | getZipStringContent | 1 | 0.02% | 956 | 99.48% |
| 54 | hexDecodeToByteArray | 1 | 0.02% | 957 | 99.58% |
| 55 | htmlFormat | 1 | 0.02% | 958 | 99.69% |
| 56 | refreshContent | 1 | 0.02% | 959 | 99.79% |
| 57 | refreshExplore | 1 | 0.02% | 960 | 99.90% |
| 58 | strToBytes | 1 | 0.02% | 961 | 100.00% |
| 59 | aesBase64DecodeToByteArray | 0 | 0.00% | 961 | 100.00% |
| 60 | aesDecodeArgsBase64Str | 0 | 0.00% | 961 | 100.00% |
| 61 | aesDecodeToByteArray | 0 | 0.00% | 961 | 100.00% |
| 62 | aesDecodeToString | 0 | 0.00% | 961 | 100.00% |
| 63 | aesEncodeArgsBase64Str | 0 | 0.00% | 961 | 100.00% |
| 64 | aesEncodeToBase64ByteArray | 0 | 0.00% | 961 | 100.00% |
| 65 | aesEncodeToByteArray | 0 | 0.00% | 961 | 100.00% |
| 66 | aesEncodeToString | 0 | 0.00% | 961 | 100.00% |
| 67 | ajaxTestAll | 0 | 0.00% | 961 | 100.00% |
| 68 | cacheContent | 0 | 0.00% | 961 | 100.00% |
| 69 | cacheFile | 0 | 0.00% | 961 | 100.00% |
| 70 | createAsymmetricCrypto | 0 | 0.00% | 961 | 100.00% |
| 71 | createSign | 0 | 0.00% | 961 | 100.00% |
| 72 | deleteFile | 0 | 0.00% | 961 | 100.00% |
| 73 | desBase64DecodeToString | 0 | 0.00% | 961 | 100.00% |
| 74 | desDecodeToString | 0 | 0.00% | 961 | 100.00% |
| 75 | desEncodeToString | 0 | 0.00% | 961 | 100.00% |
| 76 | digestBase64Str | 0 | 0.00% | 961 | 100.00% |
| 77 | downloadFile | 0 | 0.00% | 961 | 100.00% |
| 78 | evalJS | 0 | 0.00% | 961 | 100.00% |
| 79 | evalLoginActionV2 | 0 | 0.00% | 961 | 100.00% |
| 80 | evalLoginUiV2 | 0 | 0.00% | 961 | 100.00% |
| 81 | get7zByteArrayContent | 0 | 0.00% | 961 | 100.00% |
| 82 | get7zStringContent | 0 | 0.00% | 961 | 100.00% |
| 83 | getBatchContext | 0 | 0.00% | 961 | 100.00% |
| 84 | getByteArray | 0 | 0.00% | 961 | 100.00% |
| 85 | getByteArrayAwait | 0 | 0.00% | 961 | 100.00% |
| 86 | getErrResponse | 0 | 0.00% | 961 | 100.00% |
| 87 | getErrStrResponse | 0 | 0.00% | 961 | 100.00% |
| 88 | getFile | 0 | 0.00% | 961 | 100.00% |
| 89 | getGlideUrl | 0 | 0.00% | 961 | 100.00% |
| 90 | getHeaderMap | 0 | 0.00% | 961 | 100.00% |
| 91 | getInputStream | 0 | 0.00% | 961 | 100.00% |
| 92 | getInputStreamAwait | 0 | 0.00% | 961 | 100.00% |
| 93 | getKey | 0 | 0.00% | 961 | 100.00% |
| 94 | getLoginHeader | 0 | 0.00% | 961 | 100.00% |
| 95 | getLoginHeaderMap | 0 | 0.00% | 961 | 100.00% |
| 96 | getLoginInfo | 0 | 0.00% | 961 | 100.00% |
| 97 | getLoginInfoMap | 0 | 0.00% | 961 | 100.00% |
| 98 | getLoginJs | 0 | 0.00% | 961 | 100.00% |
| 99 | getLoginUiJs | 0 | 0.00% | 961 | 100.00% |
| 100 | getRarByteArrayContent | 0 | 0.00% | 961 | 100.00% |
| 101 | getRarStringContent | 0 | 0.00% | 961 | 100.00% |
| 102 | getReadBookConfig | 0 | 0.00% | 961 | 100.00% |
| 103 | getReadBookConfigMap | 0 | 0.00% | 961 | 100.00% |
| 104 | getResponse | 0 | 0.00% | 961 | 100.00% |
| 105 | getResponseAwait | 0 | 0.00% | 961 | 100.00% |
| 106 | getSource | 0 | 0.00% | 961 | 100.00% |
| 107 | getSourceNavigationContext | 0 | 0.00% | 961 | 100.00% |
| 108 | getStrResponseAwait | 0 | 0.00% | 961 | 100.00% |
| 109 | getTag | 0 | 0.00% | 961 | 100.00% |
| 110 | getThemeConfig | 0 | 0.00% | 961 | 100.00% |
| 111 | getThemeConfigMap | 0 | 0.00% | 961 | 100.00% |
| 112 | getThemeMode | 0 | 0.00% | 961 | 100.00% |
| 113 | getTxtInFolder | 0 | 0.00% | 961 | 100.00% |
| 114 | getVariable | 0 | 0.00% | 961 | 100.00% |
| 115 | getZipByteArrayContent | 0 | 0.00% | 961 | 100.00% |
| 116 | hasLogin | 0 | 0.00% | 961 | 100.00% |
| 117 | hasLoginForm | 0 | 0.00% | 961 | 100.00% |
| 118 | hexEncodeToString | 0 | 0.00% | 961 | 100.00% |
| 119 | importScript | 0 | 0.00% | 961 | 100.00% |
| 120 | initUrl | 0 | 0.00% | 961 | 100.00% |
| 121 | isLoginUiV2 | 0 | 0.00% | 961 | 100.00% |
| 122 | isPost | 0 | 0.00% | 961 | 100.00% |
| 123 | lock | 0 | 0.00% | 961 | 100.00% |
| 124 | logType | 0 | 0.00% | 961 | 100.00% |
| 125 | login | 0 | 0.00% | 961 | 100.00% |
| 126 | openUrl | 0 | 0.00% | 961 | 100.00% |
| 127 | openVideoPlayer | 0 | 0.00% | 961 | 100.00% |
| 128 | putConcurrent | 0 | 0.00% | 961 | 100.00% |
| 129 | putLoginHeader | 0 | 0.00% | 961 | 100.00% |
| 130 | putLoginInfo | 0 | 0.00% | 961 | 100.00% |
| 131 | putVariable | 0 | 0.00% | 961 | 100.00% |
| 132 | reGetBook | 0 | 0.00% | 961 | 100.00% |
| 133 | readFile | 0 | 0.00% | 961 | 100.00% |
| 134 | readTxtFile | 0 | 0.00% | 961 | 100.00% |
| 135 | refreshBookInfo | 0 | 0.00% | 961 | 100.00% |
| 136 | refreshBookToc | 0 | 0.00% | 961 | 100.00% |
| 137 | refreshJSLib | 0 | 0.00% | 961 | 100.00% |
| 138 | removeLoginHeader | 0 | 0.00% | 961 | 100.00% |
| 139 | removeLoginInfo | 0 | 0.00% | 961 | 100.00% |
| 140 | setBaseUrl | 0 | 0.00% | 961 | 100.00% |
| 141 | setLocal | 0 | 0.00% | 961 | 100.00% |
| 142 | setRedirectUrl | 0 | 0.00% | 961 | 100.00% |
| 143 | setRuleName | 0 | 0.00% | 961 | 100.00% |
| 144 | setVariable | 0 | 0.00% | 961 | 100.00% |
| 145 | showBrowser | 0 | 0.00% | 961 | 100.00% |
| 146 | singleFlight | 0 | 0.00% | 961 | 100.00% |
| 147 | splitSourceRule | 0 | 0.00% | 961 | 100.00% |
| 148 | tick | 0 | 0.00% | 961 | 100.00% |
| 149 | toURL | 0 | 0.00% | 961 | 100.00% |
| 150 | tripleDESDecodeArgsBase64Str | 0 | 0.00% | 961 | 100.00% |
| 151 | tripleDESDecodeStr | 0 | 0.00% | 961 | 100.00% |
| 152 | tripleDESEncodeArgsBase64Str | 0 | 0.00% | 961 | 100.00% |
| 153 | tripleDESEncodeBase64Str | 0 | 0.00% | 961 | 100.00% |
| 154 | un7zFile | 0 | 0.00% | 961 | 100.00% |
| 155 | unArchiveFile | 0 | 0.00% | 961 | 100.00% |
| 156 | unrarFile | 0 | 0.00% | 961 | 100.00% |
| 157 | unzipFile | 0 | 0.00% | 961 | 100.00% |
| 158 | upload | 0 | 0.00% | 961 | 100.00% |
| 159 | webViewGetOverrideUrl | 0 | 0.00% | 961 | 100.00% |
| 160 | webViewGetSource | 0 | 0.00% | 961 | 100.00% |

词表外直接调用（同时进入排序候选与覆盖分母；只报告 API 标识符，不能视作已经核实的 Android 契约）：

| 方法名 | 书源数 |
| --- | ---: |
| base64Decoder | 2 |
| deviceID | 1 |
| refreshBookUrl | 3 |

仅实现入口 Kotlin 词表的最高覆盖为 955 / 961（99.38%）；分级建议纳入词表外候选，以避免遗漏这些依赖。

## Rhino 特性与相关 JavaScript 写法

示例截取词法命中的最小结构，非保留标识符统一替换为 x；两例来自不同去重源，因此可能相同。无命中时不伪造例子。

| 特性 | 书源数 | 使用率 | 脱敏片段 1 | 脱敏片段 2 |
| --- | ---: | ---: | --- | --- |
| E4X XML 字面量 | 0 | 0.00% | 无可用命中 | 无可用命中 |
| E4X 属性访问 | 0 | 0.00% | 无可用命中 | 无可用命中 |
| E4X 后代运算 | 0 | 0.00% | 无可用命中 | 无可用命中 |
| Packages. | 54 | 1.33% | `Packages.java.lang` | `Packages.java.lang` |
| importClass / importPackage | 37 | 0.91% | `importPackage(` | `importPackage(` |
| new java.lang / java.util | 0 | 0.00% | 无可用命中 | 无可用命中 |
| .length() | 1 | 0.02% | `x.length()` | 无可用命中 |
| String(...) | 589 | 14.50% | `String(` | `String(` |
| CryptoJS. | 14 | 0.34% | `CryptoJS.x` | `CryptoJS.x` |
| let | 175 | 4.31% | `let x` | `let x` |
| const | 26 | 0.64% | `const x` | `const x` |

## URL 选项键

每个业务字符串只解析逗号后第一个选项对象的顶层键；body、headers 等嵌套对象不展开，JS 只取顶层 js/webJs/bodyJs。非严格 JSON 选项片段 1324 个（未去重）退回引号与括号感知的顶层键扫描，其 JS 值不解码。

| 选项键 | 书源数 | 使用率 |
| --- | ---: | ---: |
| method | 1074 | 26.43% |
| body | 1050 | 25.84% |
| charset | 697 | 17.15% |
| webView | 225 | 5.54% |
| headers | 88 | 2.17% |
| js | 1 | 0.02% |
| type | 1 | 0.02% |
| bodyJs | 0 | 0.00% |
| dnsIp | 0 | 0.00% |
| followRedirects | 0 | 0.00% |
| origin | 0 | 0.00% |
| resolveIp | 0 | 0.00% |
| retry | 0 | 0.00% |
| serverID | 0 | 0.00% |
| timeout | 0 | 0.00% |
| webJs | 0 | 0.00% |
| webViewDelayTime | 0 | 0.00% |

### 未知选项键

未知键按键分别统计；标签使用哈希脱敏，使用率仍以去重源总数为分母。

| 未知选项键 | 书源数 | 使用率 |
| --- | ---: | ---: |
| 未知选项键-57be31cc | 2 | 0.05% |
| 未知选项键-8f76fd50 | 2 | 0.05% |
| 未知选项键-b8bcd45a | 1 | 0.02% |
| 未知选项键-4fa3a0cc | 1 | 0.02% |
| 未知选项键-cb86eb2d | 1 | 0.02% |
| 未知选项键-aaf23206 | 1 | 0.02% |
| 未知选项键-28e5ebab | 1 | 0.02% |
| 未知选项键-a9b14c3a | 1 | 0.02% |

## 注入变量使用率

| 变量 | 书源数 | 使用率 |
| --- | ---: | ---: |
| key | 2501 | 61.56% |
| page | 2348 | 57.79% |
| result | 1606 | 39.53% |
| java | 965 | 23.75% |
| baseUrl | 656 | 16.15% |
| source | 421 | 10.36% |
| title | 297 | 7.31% |
| cookie | 261 | 6.42% |
| book | 241 | 5.93% |
| src | 112 | 2.76% |
| chapter | 106 | 2.61% |
| cache | 12 | 0.30% |
| nextChapterUrl | 11 | 0.27% |
| chapters | 9 | 0.22% |
| infoMap | 3 | 0.07% |
| speakSpeed | 0 | 0.00% |
| speakText | 0 | 0.00% |

## Rhino 特有语义的实际使用率

这里的实际使用率是语料静态候选率，不是运行时实证；String 包装、CryptoJS、let、const 本身不是 Rhino 专有特性。
- E4X 合计：0 / 4063（0.00%）。可在首版暂不支持，但零命中不能证明生态内不存在。
- Packages.：54 / 4063（1.33%）。不能以未使用为由省略；若首版不支持，必须明确排除这些候选源并进行后续兼容验证。
- .length()：1 / 4063（0.02%）。不能以未使用为由省略；若首版不支持，必须明确排除这些候选源并进行后续兼容验证。

E4X 检测 XML 字面量、属性访问和后代运算的并集；未进行完整语法解析。length() 可能是 Java 字符串、其他 Java 对象或自定义 JS 方法，静态分析不能确定；不应将全部命中直接改成 length 属性。

## 分级实现建议

- 一级：新增 16 个方法，累计 16 个，覆盖 772 / 961（80.33%）。方法：ajax, put, getString, get, timeFormat, log, toast, md5Encode, base64Decode, getElements, setContent, toNumChapter, post, aesBase64DecodeToString, encodeURI, getElement。
- 二级：新增 15 个方法，累计 31 个，覆盖 918 / 961（95.53%）。方法：longToast, startBrowserAwait, getStringList, base64Encode, startBrowser, base64DecodeToByteArray, t2s, createSymmetricCrypto, webView, head, connect, getCookie, ajaxAll, getVerificationCode, timeFormatUTC。
- 三级：其余 129 个候选方法：hexDecodeToString, refreshTocUrl, getWebViewUA, randomUUID, HMacHex, androidId, desEncodeToBase64String, digestHex, queryBase64TTF, queryTTF, refreshBookUrl, replaceFont, s2t, base64Decoder, getStrResponse, getUserAgent, md5Encode16, HMacBase64, aesEncodeToBase64String, bytesToStr, deviceID, getZipStringContent, hexDecodeToByteArray, htmlFormat, refreshContent, refreshExplore, strToBytes, aesBase64DecodeToByteArray, aesDecodeArgsBase64Str, aesDecodeToByteArray, aesDecodeToString, aesEncodeArgsBase64Str, aesEncodeToBase64ByteArray, aesEncodeToByteArray, aesEncodeToString, ajaxTestAll, cacheContent, cacheFile, createAsymmetricCrypto, createSign, deleteFile, desBase64DecodeToString, desDecodeToString, desEncodeToString, digestBase64Str, downloadFile, evalJS, evalLoginActionV2, evalLoginUiV2, get7zByteArrayContent, get7zStringContent, getBatchContext, getByteArray, getByteArrayAwait, getErrResponse, getErrStrResponse, getFile, getGlideUrl, getHeaderMap, getInputStream, getInputStreamAwait, getKey, getLoginHeader, getLoginHeaderMap, getLoginInfo, getLoginInfoMap, getLoginJs, getLoginUiJs, getRarByteArrayContent, getRarStringContent, getReadBookConfig, getReadBookConfigMap, getResponse, getResponseAwait, getSource, getSourceNavigationContext, getStrResponseAwait, getTag, getThemeConfig, getThemeConfigMap, getThemeMode, getTxtInFolder, getVariable, getZipByteArrayContent, hasLogin, hasLoginForm, hexEncodeToString, importScript, initUrl, isLoginUiV2, isPost, lock, logType, login, openUrl, openVideoPlayer, putConcurrent, putLoginHeader, putLoginInfo, putVariable, reGetBook, readFile, readTxtFile, refreshBookInfo, refreshBookToc, refreshJSLib, removeLoginHeader, removeLoginInfo, setBaseUrl, setLocal, setRedirectUrl, setRuleName, setVariable, showBrowser, singleFlight, splitSourceRule, tick, toURL, tripleDESDecodeArgsBase64Str, tripleDESDecodeStr, tripleDESEncodeArgsBase64Str, tripleDESEncodeBase64Str, un7zFile, unArchiveFile, unrarFile, unzipFile, upload, webViewGetOverrideUrl, webViewGetSource。三个级别共含 3 个词表外调用名，须核查接口归属；零频方法按后续兼容需求评估，公开成员存在不代表所有 JS 上下文均可用。

建议优先落地一级方法的同步返回值与对象桥接契约，再增加二级；Packages / Java 类型桥接和 length() 语义应独立评估，方法频率覆盖不能替代它们。

