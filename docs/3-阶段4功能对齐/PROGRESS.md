# 进度（阶段 4 · 功能对齐，轮次 3）

> 新会话先读本文件。最后更新：2026-09-14 16:40（本机时钟）。

## 1. 当前位置

- 起点 `55240af68`（阶段 3 收口）。环境：iOS 26.5 平台组件已装，模拟器 `Legado-Test`（11D3CFAE-B0CC-4C01-A767-34D43B3DB5AF），XcodeGen 2.46.0。
- 批次 1：B1 / B2 / B3 并行。

## 2. 任务表

| 单元 | 状态 | 产物 | 验证 |
| --- | --- | --- | --- |
| B1 发现页 + 封面 + 图片正文 | 在途 | `Features/Explore`、`Shared/ImageLoader`、Reader 图片 | 离线测试 + 主会话 xcodebuild |
| B2 登录 + Cookie + 校验 | 在途 | `Features/SourceLogin`、`Features/CheckSource`、LegadoCore `Login/` | 离线测试 |
| B3 本地书 TXT / EPUB | 在途 | LegadoCore `LocalBook/`、`Features/LocalImport` | 离线测试 |
| B4–B15 | 待办 | 见 PLAN | — |

## 3. 在途子 agent

（派出后登记）

## 4. 下一步与未决

- 批次 1 全部复审返修后合并跑 xcodebuild，提交，进入批次 2（B4–B7）。
