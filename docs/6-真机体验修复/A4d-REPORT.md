# A4d 数据与设置错误语义

目标：设置、书架、详情、下载、导入、备份及 Web 服务错误携带具体操作、书籍、服务器或文件上下文，消除剩余 105 行裸错误输出。工作目录为 iOS worktree；Android 数据规格仍固定 2bdd3c58b。本单元不改变备份合并规则和文件发布事务。

实现：主要模型与纯错误界面保存 UserFacingError，并为既有视图提供只读文字投影。成功/失败共用的状态区、传输事件和批量报告在显示边界使用结构化提示的 displayText。详情、分组、规则的通用操作入口逐个提供真实操作名。WebDAV 区分认证、路径和网络，备份恢复同时保留 ZIP 名与内部 JSON 名；BackupImporter 接受宿主错误格式化回调，核心默认报告行为兼容。补 JSONSerialization 的 Cocoa 格式错误与非法目录名映射。导入保留格式、损坏、权限、找不到文件等区别，在线下载保留 HTTP 状态码。取消不呈现失败，也不把规则保存取消误判为成功。

先红：三个行为测试共七个断言失败，覆盖服务器上下文、坏 JSON 的中文与文件名、本地导入操作和缺失文件，见 .build/round6/a4d-red.log。最终 Core 756/0、App 341/0。既有备份取消测试原先要求错误非空，按本轮取消语义改为 nil，同时保留未写文件、释放互斥锁及后续备份成功的断言。补 401/404/断网、权限、格式化回调原始错误与文件名测试。

模拟器 UI 1/0：同一流程验证错密码带服务器、坏 JSON 带 bookshelf.json、不支持格式带 picture.png，且选择文件入口仍可用。使用内存数据库、固定失败 client、合成 ZIP；未访问真实 WebDAV，未上传文件。初次 UI 编译发现示例页非可选状态接收可选错误的类型错误，已修正。初次 App 链接遇到 SPM 旧初始化器缓存，刷新相关测试编译后正常。

在 iOS worktree 根运行，无需外部凭据：

```sh
rtk proxy zsh -c 'CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/clang-cache" TMPDIR="$PWD/.build/tmp" swift test --package-path Packages/LegadoCore --cache-path "$PWD/.build/cache" --disable-sandbox --disable-automatic-resolution --skip-update > .build/round6/a4d-core-full.log 2>&1'
rtk proxy zsh -c 'CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/clang-cache" TMPDIR="$PWD/.build/tmp" swift test --package-path tools/appcore-check --cache-path "$PWD/.build/cache" --disable-sandbox --disable-automatic-resolution --skip-update > .build/round6/a4d-app-final.log 2>&1'
```

UI 使用 docs/HANDOFF.md 的模拟器 xcodebuild 流程，过滤 `-only-testing:LegadoUITests/ErrorPresentationUITests/testDataErrorsIdentifyServerAndFileInChinese()`；结果 .build/round6/a4d-ui2.xcresult 与 a4d-ui2.log。

原始输出：`Executed 756 tests, with 0 failures`；`Executed 341 tests, with 0 failures`；`Executed 1 test, with 0 failures`；`TEST SUCCEEDED`。

自行复审：逐处核对操作名和作用域、文件选择结果、取消过滤、后台恢复部分提交、备份锁及导入回滚。允许清单 105 -> 0；保留的 localizedDescription 仅日志与统一未知错误兜底。遵循用户禁止子代理的要求，未启动交叉复审代理。阶段 A 开发完成，下一步阶段 B；真机视觉与操作验收仍需用户使用。
