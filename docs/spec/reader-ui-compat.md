# 阅读器对齐（轮次 5 U6，在途）

规格固定为 Kotlin `2bdd3c58b`。本页随 U6 分阶段更新，不代表 U6 整体验收完成。

## 已实现的配置层

- 九宫格支持 -1 至 13 全部动作值，沿用 clickActionTL 至 clickActionBR 原偏好键。缺失或非法值回落对应默认动作；九格没有菜单时恢复中央格为菜单。
- 六套预设直接取自固定版本 `defaultData/readConfig.json`，包内资源为 reader-presets.json。首套的字体、边距、页眉页脚槽位和颜色均以资源为准。
- ReaderSettings 使用完整 ReadBookConfig，保留标题字体 / 字重、字距、背景、页眉页脚与附加字段。字号范围 5–50，正文和页眉页脚上下边距 0–400、左右 0–100，行距 0–50，段距 0–20。
- ReaderStyleStore 从备份配置表读取全部样式，支持选择、修改、导入、导出、删除；最少保留五套。共用布局使用 shareReadConfig，颜色仍来自所选样式；默认共用配置沿用第六套。
- 样式编辑写入 readConfig.json / shareReadConfig.json 的备份记录；同步当前平面偏好供现有宿主使用。备份共用布局时更新共享排版，不覆盖每套独立样式的排版。
- 配置层 App 回归 294 项通过；四项 ReaderInterfaceConfigTests 覆盖所有动作、菜单保底、预设对拍、全部配置回读和样式持久化；另有共享备份回归用例。

## 仍在接线

排版、覆盖式菜单、界面 / 设置面板、全部设置行为、独立目录与模拟器截图尚未完成。暂无 iPhone 真机测试。
