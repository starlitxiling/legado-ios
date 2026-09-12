/label ~"type:refactor"

<!-- 上一行是 GitLab quick action：提交此 issue 时会自动打 type:refactor 标签（spike 沿用此 type）。请勿删除、勿在它前面插任何内容（包括空行）；如需补充 area / priority 等自动 label，可在它下面再加一行 /label ~"area:xxx" ~"priority:P1"。前提是 GitLab 项目里这些 label 已存在；不存在时 quick action 静默 no-op。 -->

> **type**: `refactor` / **area**: `<请填本项目 area: 标签>` / **priority**: `<P0|P1|P2>`
> **优先级判断**：<一句话写为什么是这个 priority。spike 通常 P1/P2，除非阻塞了 P0 项目>

---

**问题**：<想验证什么 / 排除什么；这个调研要回答的核心问题>

**验证目标**：<什么样的结果能让我们继续 / 放弃 / 调整方向；可量化的判定标准>

**方法**：<计划怎么验证；要跑什么样例；准备什么 fixture>

**预期产出**：<spike 结束时要交付什么 — 一份测量数据 / 一段 PoC 代码 / 一个文档结论>

**关联 issue**：<指向被这个 spike 阻塞或受其结论影响的具体 issue 编号>

**scope**：<时长上限；超过这个时间就强制收手并把已有结论写进 issue>
