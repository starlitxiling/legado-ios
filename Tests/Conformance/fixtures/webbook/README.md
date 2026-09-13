# WebBook 离线语料

本目录的 HTML 与书源 JSON 全部为自造数据，使用保留域名 `example.invalid`，不依赖外部站点。

期望值参照 Kotlin 提交 `cb664b84d` 的 `model/webBook/BookList.kt`、`BookInfo.kt`、`BookChapterList.kt`、`BookContent.kt` 与 `help/book/ContentProcessor.kt` 推导；未执行 Android 基线程序。

搜索页包含一部书，详情页提供目录入口，目录的第二页覆盖同 URL 的旧章节信息。三页正文组成一章，第三页链接回首页，用来验证分页终止。正文源规则去除“广告”，用户替换规则把“海风”换为“晚风”。

`Packages/LegadoCore/Tests/LegadoCoreTests/WebBookTests.swift` 还内联构造空页、请求错误、重复正文、多链接分页、目录方向、标题图片与替换规则边界语料。

本单元保留繁简转换与重新分段的接入位置。正文 WebView 规则明确报未支持错误；购买操作只提供显式解析入口，返回值交给阅读界面处理。超时与非法替换规则使用类型化错误向调用者报告，不在核心流程中写数据库或弹窗。
