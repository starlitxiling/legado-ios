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


## P4 真实回归运行器

- 新增显式配置启用的 iOS 真书源测试，缺少配置明确跳过；逐项报告且门禁不足时真实失败。模拟器实测 4/8，保留失败，不放宽阈值。
- 命令行诊断仅由 --error-log 显式启用，标准错误摘要继续脱敏；新增离线测试检查原始错误落盘与输出不泄露。
- 私有书源、关键词、诊断文件均未加入版本控制；模拟器输入已移除。详见 REAL-SOURCES-P4.md。


## P5-1 简繁转换

- 固定 OpenCC ver.1.1.9 / 556ed22496d650bd0b13b6c163be9814637970ae，四张原始词表加 LICENSE 与 SHA-256 来源记录；无新增运行库依赖。按 Unicode scalar 最长词匹配，首选候选，保持非中文字符；两个方向按需加载并共享不可变词表。
- 正文转换在替换净化之前，标题转换同样在替换之前；重复标题检测使用未转换标题。新增 java.t2s / s2t、AppPreferences 配置和设置三选项，阅读器排版读取配置，原始缓存不转写。
- 20 组词对来自所取 OpenCC 原文件，包括皇后/后来、头发/发展、面条/面包；不宣称与 HanLP 所有版本逐字等同。Core 新增 4 项、App 新增缓存切换行为测试及偏好往返断言。
- Core 638/0、AppCore 250/0、generic iOS 构建通过，日志 p5-converter-core / p5-converter-appcore / p5-converter-ios。审查确认资源可随 SwiftPM 打包，未使用绝对运行路径。
- P5 其余六项继续实现，P4 真实门禁与去重决策仍待收口。


## P5-2/3/5/6 分段与净化策略

- ContentHelp 按 Kotlin 2bdd3c58b 移植，使用 UTF-16 索引及 Java ASCII 空白语义。提取原文件在本机 JVM 实际运行，只有 Math.random 被固定值替换；22 组句式样本及随机值 0/0.99 的 6 组分支与 Swift 逐字一致。保留上游引号启发式输出，不按主观文风重写。
- Swift 空闭区间会崩溃而 JVM 允许空 substring，审查/调试修正为半开区间；异常反向区间显式抛错。测试随机数注入保持可重复，正式行为沿用随机分段。
- 正文按单书 reSegment 配置接入；usehtml 在替换前保护、恢复为独立单行段落。图片书、本地 EPUB 默认关闭替换，单书显式配置优先于全局默认。
- removeSameTitleCache 的实际含义是 .nr 用户禁用标记，并非每处理一次就记住已删标题。BookHelp 支持标记写入/删除，Core 和阅读器按缓存目录检查标记，切换即时生效；UI 控制入口按 U6 接入。
- 新增 Core 6 项与 App 1 项，Core 644/0、AppCore 251/0、generic iOS 构建通过；最后区间错误保护修改后相关 6 项复跑通过。日志 p5-policy-*。
- scopeSource 与处理器池/热更新继续实现；不会把 scopeSource 单独勾选的书源 JSON 规则应用到正文。


## P5-4/7 书源净化与热更新（P5 完成）

- scopeSource 依据实际 Kotlin 作用于书源/RSS JSON 导入，Repository 按 enabled/scopeSource/order 查询。保留原始身份匹配作用范围与排除项；替换后必须仍为单个有效书源，错误包含可定位的规则 ID 或结果类型。
- 审查补齐 Android importReplaceSource 默认 false，导入页提供开关并保存偏好；未匹配规则直接保留对象，不做无用往返。书源预览/订阅导入均实测，非法替换不入库。
- ContentProcessor 改为可热更新实例，递归锁保护一次处理与规则更新；32 项有界池按书名/来源/配置复用。规则变更通过 GRDB observation 自动触发阅读器重排，加载期间延后，关闭时取消观察。
- 修复异步规则读取后旧 reflow 取消新排版的竞争；字体连续修改测试改用显式同步闸门，验证最终仅一次排版，不再要求过期请求必须进入等待。已打开阅读器修改规则的观察测试通过且网络请求保持 1 次。
- 最终 Core 649/0、AppCore 254/0、generic iOS 构建通过，日志 p5-final-*；详见 docs/spec/content-compat.md。P4 真实门禁仍未完成，不据 P5 完成推导整批完成。


## P6-1/2/3/5 网络路由与分页

- Header proxy 消费后移除，HTTP/SOCKS4/SOCKS5 显式端口解析与认证校验；SOCKS5 使用 iOS 17 原生配置且禁止直连回退。32 项 LRU 会话池隔离代理凭据和原域名，淘汰只等待在途任务结束。
- dnsIp/resolveIp 与全局 customHosts 接入传输，显式映射优先；保留逻辑 URL/Host/Cookie，备用 IP 顺序回退。证书按原域名验证，URLSession 不能显式设置 SNI 的限制已记入 network-compat.md。
- 普通 HTTP 与 WebDAV 共用读取中限额，WebDAV 继续禁止跨来源跳转；跨站认证头/临时 Cookie/Host 清除并重载目标 Cookie。复审发现无限超时哨兵的计时溢出风险，已单独绕过超长计时转换。
- CustomUrl 属性往返及 Kotlin 分页空项/尾页/页码越界已覆盖。新增离线协议测试验证 IPv6、配置优先级、备用 IP、会话复用/认证隔离/LRU、重定向边界；不使用真实代理或 DNS 网络。
- Core 660/0、AppCore 254/0、generic iOS 构建通过，日志 p6-routing-*。AppCore 新类型缓存出现旧符号链接错误，清理后全量重建通过。此提交未宣称 P6 上传、origin/serverID 或整个批次完成。


## P6-4/6 上传与 URL 消费（P6 完成）

- 按实际 Android upload 调用链实现 multipart，默认 mixed，fileRequest 替换/文件映射、Data/文件URL/文本/JSON、字符集、引号换行转义、HTTP retry 和去查询串均有离线断言。上传不复制普通 source headers，遵循该 Kotlin 方法未调用 headers/setCookie 的实际行为。
- 新增添加网址入口，sourceForBookURL 消费 origin 并执行模式/域名回退；模式扫描只取必要两列，不将 4198 个完整书源加载入内存。已有 URL 合并分组不请求网络；同名同作者迁移在事务中保存目录、进度和用户封面，两项 App 测试通过。
- WebDavClient.fromPath 从 serverID 查询 ServerRepository；Reader 本地恢复选择该客户端，dav/davs 与 URL 参数正确去壳。恢复保持书籍身份且已有文件不重复请求，缺少/无效 ID 与跨配置来源均明确拒绝。保持比 Android 更严格的来源边界。
- Core 667/0、AppCore 256/0、generic iOS 构建通过，日志 p6-final-*。UI 入口已编译；其视觉交互随 U1-U3 模拟器/真机检查。仍保留并明确记录 SNI、WebKit 路由及 customHosts 可解析域名等平台差异。


## U1 四入口主界面

- 底栏收为书架/发现/订阅/我的四个纯图标，保留中文无障碍名称与稳定测试 ID。搜索移到书架导航栏，书源管理成为我的首项；各页独立 NavigationStack，隐藏发现/订阅保留稳定字符串选择。
- UIKit delegate 观察器保留 SwiftUI 原 delegate 并转发可选回调，重复选择书架触发回顶，发现回到收起状态；移除观察器恢复原 delegate。主题控制选中和未选中图标颜色，原生底栏仍沿用对应 iOS 系统外观。
- 模拟器冷启动、四入口/搜索/书源管理、四主题/E-Ink 三项 UI 测试通过；实际开关将底栏 4→2→4 且导航栈保留的测试单独复跑通过。启动参数无法替代 NSNumber 偏好输入，测试改为操作设置开关；XCTest 的开关整行中心点没有改变值，改点实际控件并断言开关值。
- MainTabObserver 的重复选择/原 delegate 转发/可见索引测试通过，generic iOS 构建通过。日志 u1-navigation / u1-hidden-tabs / u1-ios；截图 assets/u1-source-entry.png。未将模拟器验证写作真机验证。


## U2 书架布局基础

- 默认标签/列表，两种分组样式、七档固定列数、布局持久化、未读/进度/更新指示、最近阅读与统计、快速滚动、手势切组均接入。长按书打开已有详情，长按分组定位并展开对应编辑项，缓存/导出保留独立选书入口。
- 阅读进度按实际 Kotlin BookExtensions 的 chapter/(total-1) 与初始隐藏语义；实际标准/增强条高为 2/4，采用该配置语义，区别于计划表格统一写 4。未读数防负值/溢出。
- 文件夹预览取每组排序前四本；刷新服务回调驱动等待集合，失败也移除，结束清空。新增回调失败/过滤及布局/文件夹测试；完整 AppCore 260/0，generic iOS 构建通过。
- 模拟器七布局切换/重启持久化、文件夹进入/长按详情两项 UI 测试及既有书架模型测试通过。首次文件夹测试误点屏幕底部露出行，测试增加可见边界检查，同时补上整行空白点击范围后复跑通过。列表、2/6 列与深色文件夹截图已人工检查。
- 日志 u2-layout-full / u2-layout-ui / u2-folder-retest / u2-layout-final-ios。远程书籍、书单导入导出、日志菜单继续补齐，尚未宣称 U2 全部完成或真机通过。


## U2 菜单与书架行为收口

- 补齐远程书籍、导出书单、导入书单、日志。书单 JSON 只含 name/author/显示简介；导入严格校验字段、按身份去重、跳过已有书籍，按启用书源顺序精准搜索并限制并行书籍数。仅预取来源 URL，逐个加载完整书源；取消不继续下一个来源、不误报普通失败。
- WebDAV 目录列表与已支持 TXT/EPUB/MOBI/AZW3/PDF 下载导入，保留 serverID，已有远程身份合并分组且保留进度；路径名称校验、下载限额、失败清理本地临时目录均已接线。默认配置不创建远端目录，整个入口只发 PROPFIND/GET。压缩包仍按 P7 后续接入，不提前宣称支持。
- 日志使用线程安全的 500 条/每条 2048 字符内存上限，HTTP 仅记方法/状态/主机，支持查看/清空/系统分享；本轮暂不跨启动持久化日志。书单与远程导入记录结果，书架更新记录失败诊断。
- 对照 Kotlin 修正手动更新范围和缓存选书范围为当前分组；启动/后台自动刷新继续按所有启用组筛选。全局与分组 onlyUpdateRead 均使用已读到末章语义。最近阅读及数量统计来自整个可见书架，已开始阅读由章节/位置判断，不以阅读时间代替。
- 新增 8 项导入/远程/日志离线测试；Core 667/0、AppCore 268/0、generic iOS 构建通过。模拟器书单导出、粘贴导入已有书、远程入口及日志展示 UI 测试通过，日志 u2-final-* / u2-menus-ui。此前七布局、文件夹交互已通过，U2 完成，继续 U3；尚未进行本轮真机验收。


## U3 搜索页

- 导航栏胶囊搜索、输入助手、历史单条删除、开始/停止、进度、80×110 结果封面、分类/简介/来源数、书架与读过标识、范围/屏蔽词/精准搜索/日志均已接入。只取来源概要，搜索时逐个加载脚本，保留有界并发和取消隔离。
- 范围编码按实际 Kotlin：分组多选，书源单选（源名::URL），显式选中禁用书源仍可搜索；已删除范围回退全部。书源单选区别于计划泛称的多选列表，实际编码和 Android 行为一致。
- UI 测试发现 SwiftUI 导航栏 TextField 的 FocusState 未获得焦点；自动聚焦输入使用局部 UITextField 桥接，在加入窗口后请求焦点。无延时猜测，实测不点击搜索框即可键入；页面与其它组件继续使用 SwiftUI。
- 来源完成次序不保证，UI 标识改为合并后的书名/作者。全量默认设置契约加入新增搜索选项；Core 667/0、AppCore 272/0、CLI 7/0。模拟器两项 UI 测试通过，覆盖自动聚焦、历史长按删除、结果、屏蔽词、范围及重启持久化。
- 日志 u3-core-full / u3-appcore-final / u3-cli-full / u3-focus-window / u3-ios-final；截图 assets/u3-input-help.png、u3-search-results.png 已检查。Android 同屏人类目视验收仍待最终交付，暂不进行 iPhone 真机测试。


## P7-1 UMD 与 AZW 入口

- UMD 头部、标题/作者/类型、章节偏移/标题、封面及分块 zlib 解码接入 LocalBook，章节 URL 为十进制索引。读取器与缓存均有大小/数量边界，缓存按文件签名失效，Files 与远程书库入口支持 UMD/AZW。
- 新增合成 fixture 与生成脚本；直接编译固定 Android Java 读取器完成元数据及首末章正文对拍，见 docs/spec/localbook-compat.md。逐字节截断、损坏压缩、非法偏移和大小上限均验证。
- Core 全量 670/0，追加缓存测试后 UMD 4/0；AppCore 272/0，generic iOS 构建通过。AppCore 初次因 SwiftPM 未重新枚举新增文件失败，刷新 manifest 后通过，没有修改业务以绕过测试。
- 日志 p7-umd-core-full / p7-umd-appcore-retest / p7-umd-cache / p7-umd-ios。U3 未签名 IPA 归档成功（u3-ipa），未安装设备。P7 其它条目继续实现，不将本提交标为本地书全格式验收完成。


## P7-2 压缩包后端与导入

- ZIP/RAR/7z 共用 BookArchive 成员元数据与逐项读取。复审 SWCompression 发现 BitByteData 短读 precondition 可终止进程、公开接口全量解压难以限制，因此改用已列入计划候选的 PLzmaSDK 1.6.1 处理 7z，RAR 仍用 Unrar.swift 0.5.4。先独立验证 LZMA/LZMA2 solid、所有截断前缀及 iOS 编译再接入；未宣称 PLzmaSDK 支持 RAR。许可证随应用资源打包。
- 校验目录穿越、绝对路径、规范化重复名、ZIP 符号链接、成员数和展开大小；原生后端只输出 Data，不交给第三方库创建路径或链接。RAR 内存输入的临时文件随归档对象释放，读操作取消、成员缺失和大小不符显式报错。
- 本地压缩包逐本导入，原归档 URL + 成员路径决定稳定身份；复导保留进度，确认副本只重试冲突成员。远程书库支持压缩包，保留 serverID/archiveEntry，缺失文件恢复读取正确成员；部分失败保留已成功入库文件，失败临时目录清理。
- Core 675/0、AppCore 275/0、generic iOS 构建通过；新增 Core 4 项、App 3 项。末次清理/计数复审后导入与远程 9 项复跑通过。日志 p7-archive-*；原生探测日志 p7-native-7z-*。不使用真实 WebDAV 写操作，未安装或测试 iPhone。系统打开、目录扫描和在线文件导入继续作为 P7 后续项。


## P7-16 系统打开、目录扫描与在线文件

- 注册书籍/压缩包文档类型，启用原位打开与文件共享；根视图 onOpenURL 将本地文件交给既有导入页。扫描目录保存 security-scoped bookmark，重启后可重新授权读取，持有目录访问权限直到导入结束；跳过隐藏项及符号链接，扫描超限明确报错。
- 在线文件限定 HTTP(S)、读取中限制 256 MiB，支持 URL 文件名与 Content-Disposition（UTF-8 filename* 优先），同一下载身份复导保持稳定。失败带 HTTP 状态码；下载源留在受管理的隐藏缓存目录供冲突确认及原始文件书签使用。
- 新增两项离线测试覆盖目录 bookmark 重载、链接过滤、扫描上限、导入、移除，以及下载导入/403/非法协议。首次测试发现对文件符号链接调用 skipDescendants 会误跳过下一个目录，改为直接跳过该文件后通过。
- AppCore 277/0、generic iOS 构建通过，日志 p7-entry-appcore-full / p7-entry-final-ios。系统分享菜单的实际选择流程尚待本地书整组模拟器验收；未把编译通过表述为设备交互已验证。P7 TXT/EPUB/PDF/MOBI 对齐继续。


## P7-7 编码检测

- 采样由 64 KiB 对齐为 512000 字节；保留 BOM/Unicode/GB/Big5 检测，补日文假名统计与系统 Foundation 多语言统计检测，并消费 HTML meta charset。ResponseDecoder 同步支持无 head 和带属性 head 的 meta。
- 合成 8 种编码及 UTF-8 期望文件，逐本读取至末章无损；另测 70000 ASCII 字节后才出现日文与 HTML 声明。未引入新依赖，也不宣称系统检测器与 Android ICU 26 个识别器完全等价。
- Core 677/0、AppCore 277/0、generic iOS 构建通过，日志 p7-encoding-core-full / p7-encoding-appcore-full / p7-encoding-ios。TXT 目录评分、JS、拆分、持久化和 URL 对齐继续。

## U7/U8 与真实回归收尾

- U7 修正 sheet 状态竞态，已有书源字段回填由 UI 自动化显式断言；模型 13/0，模拟器 1/0。U8 主菜单、主题、其它设置、备份已重排；任务执行与日志由模拟器验证，Core 定时任务 2/0，AppCore 322/0。
- 真实 4198 源冒烟回流请求头宽松解析、Jsoup DOM、raw 请求地址、JavaImporter 常用加密/URL 子集、Date 参数和 loginCheckJs 的 key/page 上下文。保留 Cookie 会话、TTS 原始字节和可调用属性的旧契约；全量 Core 747/0。
- 精选 20 源末轮 17/20，8 源模拟器 7/8。候选经预检挑选，不包装成全体随机成功率；空结果与一般脚本异常保留待核，未把网络失败算作引擎已修复。
- iPhone 按用户要求暂缓。没有将模拟器结果写成真机内存或整架更新验收。Android 同屏及备份恢复须有可运行环境，当前检查无已有 SDK/AVD/设备。
- 最终 UI 首轮 25 项中两项测试失败：布局弹窗关闭后只等待元素存在，未等待可点击；搜索页键盘遮挡时直接点击标签栏，且使用了旧的书源入口按钮标签。改为等待可点击、返回书架后进入设置并匹配实际标题，保留七布局/重启持久化与四入口断言。
- 全量报告脚本校验空输入、重复编号、未知状态及重测编号越界；实跑确认 4198/189 个输入、4198 个报告行与全部汇总数量一致。XPath 覆盖只记录 43/365 的真实字段，不将普通 URL 计入。
- 最终受影响 UI 两类复测 8/8，首轮与复测合并覆盖全部 25 个唯一测试且最新结果均通过；原始失败日志保留，不声称首轮零失败。最终 IPA 无业务代码遗漏。
