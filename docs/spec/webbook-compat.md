# WebBook compatibility (round 5 / P4)

对照 Kotlin `2bdd3c58b`，当前 Swift 实现与离线验证如下。真实网络与真机验收单独记录，不以单测代替。

## 响应、详情与脚本

- 搜索、发现、详情、目录、正文统一执行 `loginCheckJs`；SourceSession 包装客户端仅执行一次。传输失败交给检查脚本以 500 响应尝试恢复，失败时保留原始错误；取消不进入恢复。
- `infoHtml` / `tocHtml` 为进程内临时字段，不进入 JSON、数据库或备份。搜索即详情、详情即目录时复用 HTML；不同目录地址仍请求网络。
- 详情回退保留插值后的 URL 规则及 POST 选项。HTTP 最终地址不同于请求地址时按重定向处理；现有 HTTP 模型不保存重定向链，因此无法识别最终回到原地址的重定向环。
- `webJs` / `sourceRegex` 可用于所有书籍类型，但是否进入浏览器由 URL `webView` 选项控制。单独配置脚本不会强制浏览器；命令行冒烟没有安装 WebView 服务。
- `preUpdateJs` 通过 `chapterList(..., runPreUpdate: true)` 执行；目录刷新和整架刷新已传入。`java.reGetBook` / `refreshTocUrl` 仅此时可用，后者在 `fromBookInfo` 为 true 时跳过重复详情请求。重新搜索保留已有变量，更新脚本中的只读 book 快照。
- `java.getElementsRaw` 保留规则最终原始值，包括标量；`getElements` 继续仅接受数组并移除 null。

## 正文、缓存与分页

- `WebBookConfiguration` 显式注入缓存目录、并发数、特殊 HTML 开关及可选 WebView 服务。缓存路径使用现有 `book_cache` 格式；Core 不自行选择应用目录。
- 在线正文先读缓存，网络/JS 取回后落盘、补齐图片并回读。图片失败保留正文，下次仅重试缺图；纯 JS 书源使用同一缓存。阅读器保留原有消费者合并、取消和旧 JSON 缓存兼容；整本下载使用同一在线路径。本地书保留原有缓存策略，避免忽略文件版本变化。
- 多链接分页最多同时执行配置的线程数，独立书籍/章节变量副本供每页使用，结果按链接顺序拼接并合并变量差异。单下一页链仍顺序执行；取消会终止全部在途页。
- 副文在在线文字书追加，音频/视频分别存入章节 `lyric` / `danmaku` 变量；媒体副文 URL 会下载。副文网络失败记录诊断并保留正文，取消仍传播。
- `<usehtml>` 块在 HTML 格式化和实体解码前保护、之后回填。后续净化处理器的保护属于 P5。
- 在线文字替换后恢复全角缩进。纯 JS 结果返回与普通分支相同的 `payAction` / `imageStyle`。

## 批量、搜索与章节信息

- `contentBatch(book:chapters:)` 执行普通 JS 规则或纯 JS `getContentBatch(chapters, book)`，返回未回存章节。支持裸 JS 和连续 JS 包裹；非 JS 包裹拒绝执行。
- `java.cacheContent` 仅在批量期间可用；章节对象以 index 匹配，URL 必须唯一匹配，纯数字拒绝。正文套用书源替换后立即保存；空内容不算成功，批次关闭后禁止回存。
- 批量队列分组、暂停与缓存版本隔离仍在 P8 / P3h 接入；当前 App 全本下载使用统一单章缓存路径。此项不声称已经完成队列层批量调度。
- Core `SearchModel` 统一搜索页/Web 服务的四档排序：名称或作者完全相同、标签包含、名称或作者包含、其他；前三档按独立来源数排序，其余保持稳定顺序。重复项保留第一条详情及可选来源。
- `shouldBreak` 支持提前结束条目解析；`preciseSearch` 返回名称和作者完全匹配的第一项，不额外请求详情。
- 开启目录字数时，按章节 index+title 恢复旧 wordCount/variable/imgUrl。模拟更新保持 Java `Period.between(...).days` 的余数天语义，不改成总天数；跨月、月末与上下界有测试。
- 重新获取书籍后若 URL/目录/变量变化，整架刷新使用现有身份迁移事务保存，避免章节仍写向旧书籍 URL。

## 尚未完成的验收

- P4-8：计划写“全字段去重”，但 Kotlin SearchBook/BookChapter 的 equals/hashCode 实际仅比较 URL，且当前章节表以 URL+bookUrl 为主键。主实现保留现有 URL 行为；完整字段临时方案隔离为 `.build/round5/p4-fullfield-proposal.patch`，等待用户选择。
- 真实书源第一轮 8 个仅 2 个完成搜索、详情、目录、两章正文；扩展回归尚在归因，未达到计划的至少 6/8。原始书源和响应只存于忽略目录，不提交用户数据。
- 本轮尚未安装或验证有线 iPhone；按计划在批次 3/5 进行真机门禁。

## 验证与运行

在 iOS worktree 根目录运行；不需要环境变量：

```sh
swift test --package-path Packages/LegadoCore
swift test --package-path tools/appcore-check
python3 tools/conformance-run/tests/test_cli.py
```

最近完整结果：Core 634/0、AppCore 249/0；CLI 7/0，完整语料 134/142（8 unsupported）；generic iOS 构建通过。日志位于 `.build/round5/p4-*.log`。
