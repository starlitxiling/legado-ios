# 书籍详情对齐（轮次 5 U5）

规格：Kotlin `2bdd3c58b` 的 `activity_book_info.xml`、`book_info.xml`、`BookInfoActivity.kt`、`SourceCallBack.kt`、`AutoTask.kt`。

- 详情页使用 90pt 模糊封面背景、78pt 弧形过渡、110 x 160pt 封面、18pt 横滚书名、分类标签及五行 18pt 图标 / 13pt 信息。简介默认四行，展开条高 48pt；底部固定两个高 48pt 的操作按钮，顶部显示 2pt 进度。
- 从搜索或发现进入可直接阅读；没有书架记录时先保存隐藏记录，阅读本身不加入书架。换源准备阅读使用已有目录事务，保持分组与阅读位置。重新打开详情会读取编辑结果；刷新已保存书籍时写入新详情并保留阅读进度。
- 编辑、分享、定制按钮常驻；更多菜单接通刷新、更新任务、登录、置顶、书源 / 书籍变量、URL 拷贝、允许更新、TXT 长章拆分、删除提醒、缓存清理和日志。本地书提供 WebDAV 上传面板，不覆盖远端同名文件。
- 自定义按钮通过相同书源登录与变量宿主执行 `callBackJs`，注入 event/result/book/chapter；eventListener 关闭时不执行。同一页面执行期间抑制重复点击。
- 更新任务沿用 `book_update:<md5_16>`、默认 Cron、refreshToc action；先按 ID 查已有任务，再接受唯一同名同作者生成任务。编辑已有任务不重置启用状态和历史结果。任务运行器属于 U8。
- 删除提醒使用原键 `bookInfoDeleteAlert`，默认 true。书籍变量只接受字符串键值 JSON。关闭允许更新会清除更新失败位。TXT 拆分开关变化后清空目录记录，下次目录或阅读时重新解析。
- 清理缓存删除该书 URL 哈希对应的全部历史书名目录，并清理当前章节的旧版 JSON 缓存；保留其它书籍与本地原文件。
- 换源页显示来源、最新章节与响应时间，支持搜索、停止及逐源四流程校验；停止后的过期校验不会更新新一轮状态。

| 对拍输入 | Kotlin / Swift 预期 |
| --- | --- |
| 同一本书换 URL，只有一个历史生成任务 | 找到已有任务，保留 ID / 启用状态 |
| 两个同名同作者历史生成任务且 URL 均不同 | 不猜测匹配 |
| eventListener=false，存在 callback | 不执行，返回 false |
| callback 检查 event/book.name/chapter.index/result | 返回 true |
| 删除提醒没有保存值 | true |

验证：BookDetailSupportTests 覆盖任务标识、换源匹配、回调上下文及新旧缓存清理；BookDetailActionsTests 覆盖隐藏阅读记录、设置持久化、变量校验、刷新保存及进度保留；BookDetailInterfaceUITests 覆盖简介、分组、任务、换源校验与直接阅读。截图在轮次 5 assets/u5-*。

实际 WebDAV 账号未执行上传测试，网络写行为仅限既有假 HTTP 客户端用例；未进行 iPhone 真机测试。Android 同屏截图与人类目视验收仍属于最终验收项。
