# 主题与通用 UI

## 主题存储

ThemeStore 观察现有 AppPreferences；themeMode 编码仍为 0 跟随系统、1 日间、2 夜间、3 墨水屏。主题列表保留 Android themeConfig.json 的九个字段，默认四套预设来自固定 Kotlin `2bdd3c58b`。保存同名主题覆盖原项，空名称与非法色值明确报错。

ThemePalette 保存 ARGB 色值与语义颜色，ThemeColors 转为 SwiftUI 环境颜色。模式与系统外观变化即时推导色板，不重建数据库或页面导航状态。备份恢复通知触发偏好重载；透明导航栏字段保留往返，不模拟 Android 系统导航栏的透明行为。

墨水屏显示黑白配色、禁用 SwiftUI 动画，阅读器使用无动画模式 4；不覆盖保存的日夜配色或翻页模式。

## 导航栏

页面使用 legadoNavigationTitle 将 ThemeNavigationModifier 放在导航栈内部；主色用于导航栏，bottomBackground 用于底栏，accent 用于强调色。背景可见性和标题对比度使用系统 toolbar API。根 ThemeEnvironmentModifier 负责颜色环境、外观模式与动画策略，AppThemeModifier 保留背景图片、字体缩放和欢迎页。

系统生成的“更多”容器属于现有六 tab 结构，将在 U1 四 tab 改造中移除。阅读器自有阅读主题与二维码白色底板保留各自用途；其余页面布局和控件配色随 U1-U8 逐屏对齐。

## 验证

在 iOS 工作树根目录运行，无需环境变量：

```sh
rtk proxy swift test --package-path tools/appcore-check --filter ThemeStoreTests
```

主题测试覆盖四预设精确色值、模式及偏好更新、墨水屏不破坏保存值、ARGB 透明度、Android 主题字段往返和非法配置原子性。StartupUITests 提供实际页面切换与截图；Android 同屏图片需使用真实 Android 运行环境采集，不能用仿绘图代替。


## 通用组件

Shared/Components 包含 LegadoTitleBar、RefreshProgressBar、CapsuleSearchField、DetailSeekBar、LabelsBar、CoverImage、BadgeView、SelectActionBar、LoadingView、EmptyText 和 ReadStyleCircle。尺寸依据轮次 5 计划，全部读取 ThemeColors；墨水屏进度条固定显示，加载图标使用静态沙漏，工具栏以描边提示且在 iOS 26 隐藏玻璃背景。

LegadoTitleBar 放在页面 toolbar 中；页面仍使用 legadoNavigationTitle 保持系统标题与无障碍导航信息。CoverImage 复用 RemoteImage 加载链，保持 3:4，失败占位显示书名首字。LabelsBar 在可用宽度内测量文字并流式换行，长标签截断但无障碍仍保留全文。

LegadoIcon.symbol(for:) 覆盖计划的 39 个 Android 图标名，未知名返回 nil。ComponentMetrics 集中标签排布、角标 99+ 上限和进度归一化。组件画廊仅在 DEBUG 构建且携带 `-component-gallery` 启动参数时出现，不进入正式用户导航。

在 iOS 工作树根目录运行，无需环境变量：

```sh
rtk proxy swift test --package-path tools/appcore-check --filter ComponentMetricsTests
```

ComponentIconTests 在 iOS 检查所有映射符号可用；ComponentUITests 实际测试搜索提交/清空、全选与墨水屏切换，并生成 components*.png。
