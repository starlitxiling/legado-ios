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


## P2

- 主会话先以 5 项集成测试复现 8 处失败，最终增加 12 项行为测试。完整实体绑定共享变量存储，字段只读，source 方法复用既有登录和持久化实现。
- 搜索 URL 变量随 SearchBook、详情 Book 和章节结果返回；目录条目隔离变量，正文 URL、分页与标题共享章节变量。RSS 列表/正文接入文章实体和 URL 变量；目录格式脚本获得完整 book/source/chapters。
- URL executor 强持有 parser，JavaHost 与网络副本弱持有，消除 parser/session/host 环；释放测试覆盖真实脚本执行。extraParams 仅覆盖当前 URL 的读取，不污染共享存储；infoMap 支持 get。
- 按已确认计划，URL 使用规则的 chapter/book/ruleData/source 全链。固定 Kotlin AnalyzeUrl 原版仅 chapter/ruleData，属于计划明确要求的扩展；extraParams 优先级仍遵循 Kotlin。fromBookInfo 保留原名，并兼容 isFromBookInfo 别名。
- 变量 JSON 损坏会明确报错；RuleVariableStorage 和 AnalyzeRule get/put 允许传递持久化错误，调用方同步使用 try。无新增依赖。
- 全量发现只读保护提前于发现页初始化会阻止持久化方法安装，已调整顺序并通过既有回归。复查修复请求初始化重复求值 header 的问题。
- Core 574/0、AppCore 236/0、CLI 7/0；完整语料 134/142（8 unsupported），js 7/7。AppCore/CLI 首次受 SwiftPM 旧构建清单影响漏编新文件，刷新 manifest 时间戳后完整重建通过。
- iOS 构建及真机检查仍按批次门禁执行，本项未宣称完成真机验收。


## P3a

- 对照固定 Kotlin JsExtensions 的 UI/系统方法，补齐 toast/longToast、logType、randomUUID、androidId、阅读/主题配置及 Map 版本。先复现 3 项测试的 4 处失败，最终 Core 新增 6 项、AppCore 新增 2 项。
- JsPlatformServices 在锁外调用注入回调，网络副本共享当前服务；App 注入 identifierForVendor、主线程提示展示和异步配置读取。JSON 配置读取不等待 MainActor，避免同步 JS 宿主阻塞主线程时死锁。
- App 提示带书源标签，短/长时长分别为 2/3.5 秒，更新消息不会被上一条的取消任务清除。配置选中项、共享配置、备份保留字段与当前归一化设置有行为覆盖。
- logType 对常见 JS 类型输出 Rhino/JVM 名称；复杂宿主对象不模拟完整 JVM 反射类型，记录为兼容边界。UUID 使用小写标准形式，不把随机值写死成黄金向量。
- Core 580/0、AppCore 238/0，新增配置断言后宿主 6/0；generic iOS 构建通过。所有检查由主会话执行，未启动代理。


## P3b

- 先复现 6 项测试的 21 处失败；补齐 Uint8Array/ArrayBuffer/有符号数组到 Data 的桥和 8 个编解码/URL 宿主方法，无新包依赖。
- UTF-8/UTF-16/ASCII 的无效输入按替代字符处理，UTF-16 大端 BOM 与空串行为有覆盖；GBK/GB2312 等复用现有字符集映射，不可表示的字符编码为问号。
- 按 AOSP Base64 实现校验可省略 padding、显式 padding 必须完整及跳过非字母字符；按固定 Hutool 5.8.22 区分空串 null 与纯空白空数组，并支持全角十六进制数字。
- HTML 复用既有 Kotlin formatter，包括其四个全角首缩进行为；URL searchParams 保留原始键、解码值、重复键取末值，并提供 get。
- decodeURI 在固定 Kotlin JsExtensions 中不存在，本项依已确认计划实现为 encodeURI 的表单解码对应操作，不替换 JS 全局 decodeURI。
- Core 586/0、AppCore 238/0、CLI 7/0，完整语料 134/142。少数字符集的损坏字节仍遵循 Foundation 的显式失败，见兼容文档。


## P3c

- 以固定 Kotlin JsEncodeUtils/crypto 包为规格，补齐 27 个摘要、HMAC、加密、签名入口；对称/非对称对象提供链式配置与字节桥。
- 固定 AES/DES/3DES 密文、NIST AES 向量、OpenSSL RSA 密钥/密文/签名验证通过；新增 9 项测试覆盖旧接口特殊行为、四种构造重载、长消息分段、无效参数与密钥导入导出。
- CryptoJS 4.2.0 原版源码与 MIT 许可证作为 SwiftPM 资源打包，按上下文首次访问懒加载；随机数来自 Security，测试覆盖书源库初始化、口令 AES 往返与随机请求大小限制。
- 自查移除旧重复摘要/AES实现及方法名，修复 Hutool Base64 密文中的加号/斜杠解码、无 IV 解密以及验签异常被吞的问题。更新旧 CryptoJS 缺失断言。
- Core 595/0、AppCore 238/0、CLI 7/0；generic iOS 构建通过，资源成功打包。算法范围及 Java 平台对象边界记录于 js-host-compat.md，未宣称 Android 实机对拍或本轮真机验收。


## P3d

- 先复现 4 项时间测试的 12 处失败，补齐 timeFormat 自定义格式与 timeFormatUTC；第三参数严格按 Android 的毫秒偏移单位处理。
- 覆盖日夜时区、负时间戳、小于一秒的偏移、Java 的 S/u/X/Z 与连续字段/引号语义；无效格式、非有限时间、Int32 偏移越界均报错。模式按字段格式化，避免拼接转义字符串造成相邻字面量歧义。
- Core 全量 599/0；本地化文字字段使用 Foundation 数据，未运行 Android 对拍。AppCore/CLI/iOS 在接下来的批次 1 合并门禁重跑。


## U0

- ThemeStore 复用 AppPreferences，ThemePalette/ThemeColors 集中 ARGB 与语义颜色；四模式/四预设实时更新并与主题备份互通。补齐 transparentNavBar 日夜字段往返，保存空名称与编码错误显式传播。
- 根视图统一外观、强调色与墨水屏策略，移除重复主题控制。66 处标题接入导航栈内部的主题修饰器，覆盖原生导航栏/底栏；现有静态 Theme.accent 已全部迁移。
- 墨水屏使用黑白色板与灰度显示，禁用 SwiftUI 动画，阅读器临时覆盖为无动画模式 4，不写坏保存的阅读配置。系统选择器改为带明确主题标签的整行 Menu，避免缓存旧 tint 与局部点击区域问题。
- 新增 6 项主题行为测试，AppCore 全量 244/0；generic iOS 构建通过。模拟器启动 3/0、冷启动 UI 1/0、四预设与墨水屏 UI 1/0；最终菜单修正单项复跑通过。截图见 assets/theme-*.png。
- 目视确认墨水屏已无彩色控件。旧六 tab 的系统“更多”仍导致双导航栏，按 U1 四 tab 改造移除；各功能页面布局与语义配色按 U1-U8 继续对齐。当前没有 Android 运行环境截图，未伪造同屏对照。


## U9 与批次 1 门禁

- 新增计划全部 11 类通用视图及 39 个图标映射；颜色来自 ThemeColors。标签按可用宽度测量并流式排布，封面固定 3:4，搜索框 30pt、配色圆块 48pt、进度条 2pt。
- 墨水屏禁用不定进度动画，使用静态沙漏，角标/标签/标题使用描边；iOS 26 组件工具栏隐藏玻璃背景，深色主色标题使用对比文字。没有添加第三方依赖。
- 新增 3 项 ComponentMetricsTests；iOS ComponentIconTests 验证全部 SF Symbols 存在；ComponentUITests 验证真实搜索提交/清空、全选及墨水屏切换。DEBUG 画廊不进入正式导航；真实截图 assets/components*.png 已检查。
- 批次 1 最终状态：Core 599/0（P3d 后 Core 未改）、AppCore 247/0、CLI 7/0，完整语料 134/142（8 unsupported）；generic iOS 构建通过。启动注册 3 项、冷启动 UI 1 项在最终根视图上复跑通过；主题与组件交互均通过。
- 真机按计划在批次 3/5 验证，本批仅模拟器和构建，不声称新版本已经在 iPhone 完成验收。


## P4 流程基础（真实门禁与去重取舍待收口）

- 新增响应检查/HTML 复用/请求身份、正文缓存/副文/WebView、受限分页、共享搜索排序、目录刷新宿主及批量正文回存。未增加外部依赖；Core 配置显式接收目录和平台服务。
- 新增 35 项 Core 测试，覆盖五入口、原始错误与取消、单次检查、POST 规则、缓存免请求与图片补全、分页乱序/限并发/取消、精准搜索提前终止、Java Period 语义、批量重复 URL 拒绝与章节对象回存。
- 自查补齐本地下载缓存保留及整架刷新书籍 URL 迁移，新增 2 项 App 测试；既有阅读取消/共享下载/改章名兼容均通过。App 的一次 EXC_BAD_ACCESS 定位到旧 Book 布局对象文件，清理 SwiftPM 后全量复跑消失。
- 真实书源复现并修复：单独 webJs 不应强制 WebView；URL 前置副作用表达式留下的空白应先移除再解析。浏览器能力仍要求平台注入，命令行不伪造该能力。
- Core 634/0、AppCore 249/0、CLI 7/0（134/142，8 unsupported）、generic iOS 构建通过；详见 p4-core-final / p4-appcore-final / p4-ios-final / p4-cli 日志。
- P4-8 的全字段方案与 Kotlin 实际实现及数据库主键冲突。临时方案已移至忽略目录补丁，主分支保留原行为以继续测试，不将沉默视作用户决策。
- 真实首轮 2/8 通过，扩展验证继续；P4 不标记完成。缓存批量调度/版本隔离按 P8/P3h 接线，处理器特殊 HTML 按 P5 接线。详细边界见 docs/spec/webbook-compat.md。
