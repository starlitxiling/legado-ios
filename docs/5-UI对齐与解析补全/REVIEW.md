# 轮次 5 审查记录

## P0

- PDF 分段标题已与 Kotlin `2bdd3c58b` 的 `PdfFile.kt:217` 核对，为 `分段_0` 等。修复保存后丢失大纲的合成 fixture，保留真实书签断言，并覆盖 1/10/11/20/21 页分段边界。Core 549 项通过；AppCore 共享 PDF 5 项通过。
- 独立审查发现 P1：`App/Sources/Features/Backup/BackupViewModel.swift` 恢复入口未传入本地密码及当前偏好。恢复需读取调用时最新快照，覆盖模型创建后修改密码、加密源状态恢复及已有 WebDAV 密码保护。
- 独立审查发现 P2：`tools/conformance-run` 在只有非用例 JSON 时以 0/0 返回成功。需使零用例失败，且不能把损坏的显式用例悄悄当辅助 fixture 跳过。
- 两项审查问题已修复并核验 diff：AppCore 236 项、CLI 7 项通过；完整语料仍为 134/142，8 条 unsupported 明确使进程退出 1。
- AES 固定向量、释放池生命周期、缺目录恢复与二次缓存命中的既有测试已核验；generic iOS 构建和模拟器启动测试通过。
- 审查采用独立代理及 `code-review-excellence`，主会话抽查了 diff 与报告中的源码位置。本机缺少计划引用的 `/review-loop`。

原始日志和代理报告保存在 gitignored 的 `.build/round5/`，不提交第三方内容或凭据。

用户随后要求不再使用子代理；后续所有实现、审查和验证均由主会话亲自执行。

## P1

- 主会话按 Kotlin `2bdd3c58b` 的 AnalyzeRule、AnalyzeByJSoup、NetworkUtils 核对七项行为，先复现 19 个断言失败，再完成修复。
- CSS 组合子项不再二次切分；保留独立 JSoup 入口的组合支持。空 CSS 子项和空集合跨界区间明确抛错。
- 普通映射按首段键读取；JSONPath 对象保留选择器语义；JS 对象快照保留 NativeObject 行为，不持有 JavaScript 上下文。
- URL 字符串/列表在 AnalyzeRule 中统一按重定向地址解析，去重并保留当前页链接；补齐 JS 宿主 URL 重载。
- setContent 拒绝 nil/NSNull，失败不覆盖旧内容，成功重置 DOM 缓存。XPath/JSONPath 当前实现按次解析，无持久缓存；通过三类内容切换验证新内容生效。
- 新增 RuleParityTests 13 项，包含对象释放和宿主调用路径。Core 全量 562/0，AppCore 236/0，CLI 7/0；CLI 中完整语料 134/142，8 unsupported，基线无回退。
- 所有断言期望根据上述固定 Kotlin 源码推导，本次未运行 Android Kotlin 端；iOS 构建在批次 1 合并门禁执行。
