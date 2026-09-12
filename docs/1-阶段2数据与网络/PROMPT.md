# 需求：阶段 2 数据与网络

## 背景

阶段 1 已在 `Packages/LegadoCore` 落地规则引擎核心（8 个单元，121 项测试，一致性用例 142/142），但全部离线：`java.*` 的网络方法只是桩，规则引擎没有真实的 HTTP 请求、Cookie、字符集解码，也没有书源实体、导入解析、书架与章节的持久化。没有这一层，引擎无法对着任何真实书源工作，MVP UI 也无从建起。

## 目标（来自 `docs/0-iOS适配规划/PLAN.md` §4 阶段 2）

1. **网络层**：URLSession 封装，按源应用 `UrlOptions`（method / headers / body / charset 含 GBK 解码 / retry / followRedirects / timeout），Cookie 存储语义对齐 Kotlin `CookieStore`；`dnsIp` 与代理在 iOS 无原生对应，文档标注为不支持。
2. **java 宿主网络方法**：`ajax` / `post` / `get` / `head` / `connect` / `ajaxAll` / `getCookie` 等一级、二级方法建立在网络层之上，失败语义对齐 Kotlin（返回错误字符串并继续，见 `docs/spec/js-host-compat.md` 第 ② 类差异）。
3. **书源与规则实体**：`BookSource`（含 6 组规则对象）、`ReplaceRule`、`Book`、`BookChapter`、`SearchBook` 等 MVP 所需实体，JSON 导入解析对齐 Kotlin 的 Gson 宽松反序列化（规则字段既接受对象也接受 JSON 字符串；弱类型容错）。
4. **WebBook 流程**：搜索 / 发现、书籍详情、目录（含分页）、正文（含分页与源级替换）四条流程按 `model/webBook/` 移植，用可注入的 HTTP 客户端做离线 fixture 测试。
5. **持久化与备份**：GRDB 建 MVP 表；Legado 备份包（书源 / 书架 / 替换规则 / 阅读进度 JSON）导入；WebDAV 客户端。

## 完成判据

- 全部网络行为可用假 HTTP 客户端离线测试，测试不发真实请求（宪法「环境是被测行为的输入」）。
- 一份自造的 Legado 备份包导入后，书源、书架、替换规则、阅读进度落库可查。
- 用一个公开书源在真机 / 模拟器上人工跑通「搜索 → 详情 → 目录 → 正文」（人工冒烟，不进 CI）。

## 约束

- 沿用阶段 1 的工作模式：Codex 实现、独立上下文复审、按 Kotlin 返修；每个单元产物落盘并 commit 后再开下一个；`PROGRESS.md` 断点续传。
- 不写 UI；不动阶段 1 已提交的引擎公开接口，除非报告里逐处列出。
- 只有人知道的参数（WebDAV 测试服务器地址与凭据、人工冒烟用的书源）列为待确认项，不猜；离线测试用本地 mock。
