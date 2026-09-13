# 真实书源冒烟

在本目录执行 `swift build`，随后执行：

```sh
.build/debug/WebBookSmoke --source source.json --keyword 航海
```

`--source` 是本地 UTF-8 书源 JSON；数组默认选第一条。
`--source-index` 和 `--pick` 均从 0 开始，默认 0。
`--chapters` 默认 2，抓取前 N 个非卷标题章节；不足时抓取全部。
`--timeout` 默认 60 秒，限制每次 HTTP 请求，包含该请求的重定向。
它不限制整个流程时长，也不限制同步书源 JavaScript 的运行时间。
流程执行搜索、详情、目录和正文；每步输出耗时，成功返回 0，失败返回 1。
字数按非空白 Swift Character 计数；摘要在脱敏后取前 60 字。
URL 只输出域名与路径长度；不输出请求头、完整 URL、错误关联文本或书源原文。
文本摘要过滤 URL、凭据样式、邮箱与长令牌，但无法识别任意自然语言隐私。
只使用可信的公开书源和公开内容；书源 JavaScript 会在本机执行。
不支持 sourceUrls 间接导入与 mainJs 书源，不绕过登录、付费或反爬。
不写日志文件，也不写数据库。
执行 `swift test` 运行 ReplayHttpClient 离线测试，不访问真实站点。
离线 fixture 来自仓库 `Tests/Conformance/fixtures/webbook`。
