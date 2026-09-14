# 备用图标渲染工具

macOS SwiftPM 命令行工具，使用系统 CoreGraphics、Foundation XMLParser 和 ImageIO，无第三方依赖，Swift 语言模式为 5。

在本目录执行 `bash check.sh`，离线运行 XCTest 并从固定测试素材生成 App 的 12 张备用图标。直接调用 `.build/debug/IconRender <res目录> <输出目录>` 可以渲染另一份 Android 资源。

测试素材来自 Android 提交 `2bdd3c58b` 的 `app/src/main/res`，保留原始 XML；仅包含六套 adaptive-icon、所引用的九份 drawable 和两份颜色资源。测试输出与构建缓存均位于本目录 `.build/`。

支持 SVG 路径 M、L、H、V、C、S、Q、T、A、Z 及相对形式和隐式重复；椭圆弧按最多 90 度一段近似为三次贝塞尔。支持 VectorDrawable 的 viewport、填充与描边、透明度、分组变换、裁剪和颜色引用；不支持渐变、trimPath 或其他 drawable 类型。遇到不支持的 XML 元素会报错。

按 B16 任务约定，在 108dp 坐标系合成背景与前景，取中心 72dp 正方形，输出 120×120 和 180×180 RGB PNG，不预制圆角，透明图层合成在白色底上。未生成额外 iPad 专用尺寸；iPad 声明复用任务指定的两种尺寸，实际设备效果由主会话验证。

| 名称 | Android 前景 | 120×120 预览描述 |
| --- | --- | --- |
| launcher1 | ic_launcher2 | 黄色底上为白色卷轴，卷轴内写深色“阅读”，右下带红色印章。 |
| launcher2 | ic_launcher5 | 灰蓝底上为浅色“阅读”和 Read 字样，下方有浅蓝展开书页。 |
| launcher3 | ic_launcher3 | 近白底上为黑色毛笔“书”字，外围有暗红色不闭合笔刷圆环。 |
| launcher4 | ic_launcher4 | 白底上为蓝色读书人物和不闭合圆弧。 |
| launcher5 | ic_launcher6 | 近白底上为 Read 字样，R 呈蓝色，其余字母为深灰色。 |
| launcher6 | ic_launcher7 | 浅灰底上为蓝色“阅读”和 Read 字样，下方有黄色展开书页。 |

`App/project.yml` 使用同名 CFBundleIconFiles，在 iPhone 和 iPad 的 CFBundleAlternateIcons 中登记。工具不会运行 XcodeGen，也不会修改 Xcode 工程或主图标。
