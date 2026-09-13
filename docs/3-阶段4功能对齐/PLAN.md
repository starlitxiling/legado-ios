# 阶段 4 计划：功能对齐 Android

> 状态：人类以 `/goal` 授权（2026-09-14）「先都做了，没必要急着真机测试」。

## 1. 单元划分（按依赖分批）

| 批次 | 单元 | 内容 | Kotlin 规格 |
| --- | --- | --- | --- |
| 1 | **B1 发现页 + 封面 + 图片正文** | `exploreUrl` 解析（分组 / 分页 / `{{page}}`）与发现页；封面下载缓存（`coverDecodeJs`）；正文图片（`imageStyle`、图片下载与阅读器内渲染） | `model/webBook/BookList`(explore)、`help/book/BookHelp.saveImage`、`model/ImageProvider`、`ui/book/explore` |
| 1 | **B2 书源登录 + Cookie + 校验** | `loginUrl` 网页登录（WKWebView 会话 Cookie 回写）、`loginUi` 表单登录、`loginCheckJs`、`getVariable / setVariable`；Cookie 管理；书源校验（搜索 / 发现 / 详情 / 目录 / 正文逐项检查） | `model/login/*`、`help/http/CookieStore`、`service/CheckSourceService`、`model/CheckSource` |
| 1 | **B3 本地书 TXT / EPUB** | 文件导入（Files app）、编码探测、`TxtTocRule` 目录规则、EPUB（zip + OPF + NCX / nav + XHTML → 正文）、本地书在书架与阅读器中的接入 | `model/localBook/{LocalBook,TextFile,EpubFile}`、`data/entities/TxtTocRule`、`modules/book` |
| 2 | **B4 WebView 抓取** | `BackstageWebView`：`useWebView`、`@webjs:`、`java.webView*`、`getVerificationCode`、`startBrowser`；WKWebView 挂在 window 上零尺寸运行，仅前台 | `help/http/BackstageWebView`、`JsExtensions` webView 段 |
| 2 | **B5 纯 JS 书源** | `mainJs` 书源的 `JsSourceEngine` 与 `JsSourceConfig.extract` | `model/jsSource/*` |
| 2 | **B6 听书 TTS** | 系统 TTS（AVSpeechSynthesizer）与在线 `HttpTTS` 源、后台音频、锁屏控制、定时、朗读进度与阅读器联动 | `service/{BaseReadAloudService,TTSReadAloudService,HttpReadAloudService}`、`data/entities/HttpTTS` |
| 2 | **B7 本地书 MOBI / PDF** | MOBI 解析（`lib/mobi` 纯逻辑移植）、PDF（PDFKit 分页文本） | `model/localBook/{MobiFile,PdfFile}`、`lib/mobi` |
| 3 | **B8 书源编辑与管理进阶** | 书源编辑器（全字段表单 + JSON 编辑 + 调试面板）、分组 / 排序 / 批量启停、导出与分享（JSON、二维码）、替换规则编辑器、TXT 目录规则与字典规则管理 | `ui/book/source/edit`、`ui/book/source/debug`、`ui/replace/edit`、`ui/dict` |
| 3 | **B9 阅读器进阶** | 标题样式、字体选择、翻页动画（覆盖 / 仿真 / 滚动）、自动阅读、书签界面、高亮与批注（`BookHighlight`）、段评（`ReviewRule`）、章节缓存进度显示 | `ui/book/read/*`、`help/config/ReadBookConfig`、`data/entities/{BookHighlight,Bookmark}` |
| 3 | **B10 书架进阶与下载** | 分组编辑、书籍信息编辑、更新章节（前台任务 + `BGAppRefreshTask`）、缓存整本、导出 TXT / EPUB | `ui/main/bookshelf`、`service/CacheBookService`、`help/book/BookHelp`、`ui/book/cache`、`ui/book/info/edit` |
| 4 | **B11 RSS** | 订阅源导入、文章列表（规则解析）、WKWebView 阅读、收藏 | `model/rss/*`、`data/entities/{RssSource,RssArticle,RssStar}`、`ui/rss` |
| 4 | **B12 漫画 / 音频源** | `bookSourceType` 1 音频（AVPlayer + 后台）、2 图片（漫画阅读器）、3 视频留桩 | `model/webBook` type 分支、`service/AudioPlayService`、`ui/book/manga` |
| 4 | **B13 备份上传与设置对齐** | 备份打包与 WebDAV 上传（测试只用假客户端）、本地备份导出、主题 / 语言 / 其他设置项对齐 | `help/storage/Backup`、`help/AppWebDav`、`ui/config` |
| 4 | **B14 局域网 Web 服务** | 前台 HTTP 服务（书架 / 书源 / 阅读 API 与内置 Web 页面）、前台限定 | `web/*`、`service/WebService` |
| 4 | **B15 实体与表补齐** | `SearchKeyword`、`HighlightRule`、`ReadRecordDetail`、`Server`、`KeyboardAssist` 等剩余实体、表与备份导入 | `data/entities/*`、`help/storage/Restore` |

## 2. 关键设计决策

| 决策 | 结论 |
| --- | --- |
| WKWebView 无头 | 挂到 key window 的零尺寸子视图，仅前台；超时与并发上限；记入 network-compat |
| 后台能力 | 听书用 `UIBackgroundModes: audio`；更新章节用 `BGAppRefreshTask` + 前台；Web 服务只前台 |
| 本地文件 | `UIDocumentPicker` + security-scoped bookmark 持久化；导入时复制进沙盒 |
| 第三方依赖 | 尽量不加；EPUB 用自实现 zip + SwiftSoup；MOBI 移植 `lib/mobi`；二维码用 CoreImage / AVFoundation |
| iOS 不可实现 | 悬浮窗、应用内更新、系统级 TTS 引擎选择、ContentProvider 对外 API、Quick Settings Tile：标注不做 |

## 3. 批次推进

每批内单元并行（文件不重叠），批内全部复审返修后合并跑一次 `xcodebuild build` 与打包，再提交，进入下一批。
