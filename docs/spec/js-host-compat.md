# JS 宿主已知兼容差异

对照版本为 Kotlin/Rhino `cb664b84d`；本文记录离线阶段边界，不把差异当作兼容行为。

## Java 对象、语言语义与共享库

| 差异 | 最小示例与当前结果 | 影响 |
| --- | --- | --- |
| java 方法返回原生 JS 字符串和数组，不模拟 Java 对象 | `java.md5Encode('abc').length()` 抛 TypeError；应使用 `.length`。`java.getElements('tag.p').size()` 不可用，应使用 `.length` | 依赖 Java String/List 方法的旧书源需要适配；普通 JS 规则的数值最终输出仍按 Double 转换，模板才去掉整数小数部分 |
| 不执行 Rhino 的 let/const 归一化 | `{ let x=1; } x` 在 JSC 抛 ReferenceError；`{ const x=1; } x` 同样不可读 | Kotlin 的归一化器对满足条件的块外读取恢复可见性；依赖这类旧作用域行为的脚本会失败 |
| 默认不注入 CryptoJS | `typeof CryptoJS` 返回 `undefined`；`CryptoJS.MD5('abc')` 抛 ReferenceError | 依赖 CryptoJS 的书源不能直接执行；宿主可用 `libraryInitializer` 注入库，系统 AES/MD5 方法不等于 CryptoJS 全局对象 |

原文依据：`modules/rhino/src/main/java/com/script/rhino/RhinoContext.kt:143-258`、
`app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeRule.kt:914-922`。
归一化发生在解析之后；不能从 `let` 改成 `var` 推断同作用域重复声明一定被 Kotlin 接受。
本机未运行 Rhino；JSC 重复 `let x` 抛 SyntaxError，重复 `var x` 可执行，这仅是 JSC 实验。

## 离线宿主桩

当前 ajax/post 等网络方法、toast、文件及 cookie/cache 骨架抛“未实现”异常。
例如 `java.ajax('https://example.invalid'); 'continued'` 在当前实现中中断，除非脚本自己捕获异常。
Kotlin 的 `ajax` 捕获请求异常后返回 `stackTraceStr`，脚本能将错误当作字符串继续处理。
依据：`app/src/main/java/io/legado/app/help/JsExtensions.kt:180-194`。
这不是所有网络方法统一的错误契约；阶段 2 必须逐方法核对返回类型、异常与取消语义。
这些桩表示离线阶段的能力缺失，不是网络失败的兼容实现；阶段 2 接入网络层后需要对齐。
测试引用本文的“已知差异”断言仅防止能力边界悄然变化，不可据此宣称 Kotlin conformance 已通过。
