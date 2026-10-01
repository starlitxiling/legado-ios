# 轮次 7 进度：遗留修复与功能补齐

## 当前阶段
- 2026-09-29：用户要求补齐轮次 6 复审遗留与 Android 缺失功能（音量键翻页除外），并明确要求主会话亲自实现、不开子 agent（偏离 CLAUDE.md 委派规则，已在各 commit message 留痕）。起点 `703b3a663`。
- 全部 8 个单元已提交；最终回归 Core 768/0、App 378/0、LegadoTests 17/0、UI 53/1（翻页测试按旧规则断言，已改测试并单独重跑 1/0），见 .build/round7/final-summary.md。

## 任务表
| 单元 | 内容 | 提交 | 验证 |
| --- | --- | --- | --- |
| H1 | 封面先查内存缓存再加载，本地封面按文件变更失效，已取消任务不再解码 | 9b731e731 | CoverBitmap 2/0 |
| H2 | 书源脚本错误中文提示（JS 内可见 description 不变） | 367265eb8 | Core 765/0 |
| H3 | 错误可原样抛出去双层包装；发现/换源重试；翻页松手按 Android 回拉取消；书级动画优先于墨水屏；行距标签；触摸距离按像素换算；下划线跳过缩进 | c5210727f | App 374/0，构建通过 |
| H4 | 偏好读取接受启动参数字符串值；标签页 UI 测试等待开关生效 | 772e967d1 | AppPreferences 8/0 |
| H5 | 详情页换封面（默认封面/封面规则/各源精准搜索） | 3c7a7c0e8 | BookDetailActions 5/0 |
| H6 | 视频书源播放（AVPlayer，选集、自动下一集、进度保存；DASH 给出说明） | 5206b4447 | VideoLibrary 1/0 |
| H7 | 文件下载书源（可读格式导入书架，其他保存到文件 App） | 4e9e44e7e | WebFileResolver 3/0 |
| H8 | 补主图标，备用图标可切换；渲染工具支持线性渐变 | 3eab58ed4 | icon-render 8/0，UI 1/0 |
| H9 | 仿真模式手势翻页后不再重播卷页动画 | 0bc97c704 | 仿真 UI 1/0，真机待确认 |
| H10 | 书源脚本同步读状态改走写队列，修复整架更新死锁（真机 0x8BADF00D，6 协作线程阻塞） | e4144667a | Core 769/0，真机整架更新不再卡死 |
| H11 | 目录拉取失败显示可操作占位页；新备份提示每次启动一次、关闭后不再提示 | e0fcc7ba6 | App 380/0 |
| H12 | 缓存同一本书连续 10 章失败自动暂停并显示原因 | 7543def29 | Core 771/0 |
| H13 | 全 App 弹出页补齐关闭按钮（脚本排查 46 处） | 40d79cd1c | 构建通过 |
| H14 | 下载中心仅在进度变化时刷新、限制列表行数（Time Profiler 定位全局卡顿） | 8800c5820 | Core 772/0，App 381/0，真机用户确认流畅 |

## 真机问题记录（2026-10-01）
- 《宝鉴》：酷我小说书源目录接口返回空（Mac 复现 emptyToc），书源失效，需换源。
- 《凡骨》：35小说旧域名 301 到 www.35ge.info，直连被重置连接，需 VPN 或换源。
- 签名：个人团队 R6593A6KK4，描述文件 7 天有效（本次到 2026-10-06），见 memory ios-device-signing。

## 未做与限制
- 音量键翻页：用户决定不做。
- 视频弹幕、DASH（MPD）播放不支持；Core 报告类错误（整架更新/缓存/定时任务）沿用 LocalizedError 文案，未改走 App presentation。
- 2026-10-01 在 fc378743b 上完整回归：LegadoTests 17/0，UI 53/1；失败项 SourceInterfaceUITests.testListSelectionAndEditorTabs 为并发打包时的等待超时，单独重跑两次均 1/0（.build/round7/final2-*.log）。视频、文件下载、换封面已由用户真机验证。

## 下一步
改用 SideStore 侧载续签，任务书 SIDESTORE.prompt.md 已交用户驱动 Codex 执行。

2026-10-01 已用个人团队 R6593A6KK4 自动签名（描述文件到 2026-10-06）覆盖安装到 iPhone（com.starlitxiling.legado.ios，提交 90e63d928），待用户真机验收。
