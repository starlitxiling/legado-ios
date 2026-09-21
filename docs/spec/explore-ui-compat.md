# 发现页对齐（轮次 5 U4）

规格：Kotlin `2bdd3c58b` 的 `ExploreAdapter.kt`、`ExploreFragment.kt`、`ExploreKind.kt` 及 `ExploreShowActivity.kt`。

- 发现页按已启用且有发现规则的书源展示；单开手风琴，展开时定位，重选发现 tab 收起分类。分组筛选按完整分组名匹配，顶部提供书源管理。
- 行内显示书源名、20pt 方向箭头与加载状态；分类复用流式布局。长按提供编辑、置顶、登录、限定当前源搜索、刷新和删除。
- JSON 控件支持 url、text 输入框、select 选择器、toggle 循环状态与 button；保留 chars/default/viewName，动态显示名称及 action 通过同一 infoMap/source 变量宿主执行。文本动作防抖 600ms，选择器初始化不触发动作，空选项不发生取模错误。
- 控件值在切换书源时保留；infoMap.save 持久化至 SourceStateRepository，java.reUiView 重新求值分类，java.upUiData 合并控件数据。跨书源过期响应不会替换当前分类，同一源较旧的控件动作不会覆盖新结果。
- 书单提供横滚分类标签，结果行复用 SearchResultRow；末行出现时请求下一页，保留失败重试与手动加载入口。
- 下拉刷新只作用于竖向书单，避免横向分类栏继承刷新行为导致文字被移出裁剪区域；UI 用例直接检查分类文字渲染像素。
- UI 使用枚举后的分类快照；刷新清空分类时不会让旧视图的索引访问新数组。模拟器曾复现数组越界，修复后由同一交互用例回归。

验证：ExploreControlTests 核对类型、选项、动态名称、infoMap 持久化与 source 变量；ExploreImagesCheckTests 核对筛选、单开、排序、删除、未保存控件值以及受控延迟响应；ExploreInterfaceUITests 在模拟器验证控件、换源展开、分类书单与筛选。截图见轮次 5 assets/u4-*。未进行 iPhone 真机测试。
