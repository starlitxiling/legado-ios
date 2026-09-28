# 轮次 6 最终交付

2026-09-28：PLAN.md 的 A1-A4、B1-B4、C1-C3 代码实现全部完成，分单元提交；遵照用户要求全程未启动子代理。各单元实现、规格差异、红绿测试和复审证据见同目录报告。

## 最终验证

- App 单元测试：358 项，0 失败，`.build/round6/c3-app.log`。
- 最终模拟器回归：7 项，0 失败，`.build/round6/final-ui.log` / `.xcresult`。覆盖大字号、500 本快速定位与菜单、空书架、停止与重新更新、原生仿真双向翻页、跨章连续滚动、标签栏及前后台导航。
- 书架补充复审测试：2 项，0 失败，`.build/round6/c1-review-green.log` / `.xcresult`。覆盖独立分组排序下置顶、移出确认及保留其他书籍、空文件夹导入引导。
- Core 最近全量结果为 757 项、0 失败（B2）；之后未修改 Core 代码。
- Release：`ARCHIVE SUCCEEDED`，`.build/round6/phase-c-final-release.log`。
- ZIP 全项 CRC 检查通过，主可执行文件为 ARM64；已复核最大辅助字号截图，图标与文字不再重叠。

## 安装包

- 文件：`dist/Legado-1.0-794cc4077.ipa`
- 对应代码提交：`794cc4077`，版本 1.0，9674104 字节，未签名。
- SHA-256：`70103b0125bc9944d40ee7725f6c4959907d2e869ee81033c2874aee71e8da53`。
- 工程包标识为 `com.legado.ios`；将来覆盖手机现有“阅读”时，仍须使用 `com.starlitxiling.legado.ios` 并配套有效描述文件签名，沿用之前的覆盖安装方式。

本次未安装或执行真机测试：iPhone 在 devicectl 中为 unavailable；旧描述文件有效期至 2026-09-23 14:12:17 UTC，已过期。此前 `.build/round6/sign-iphone-app.sh` 的暂存应用属于阶段 A，不能直接用作本次最终交付；重新安装必须先从上述最终 IPA 准备应用并更新描述文件。没有再次访问登录钥匙串或尝试已被拒绝的 Terminal 自动化路径。

## 复现

在 iOS worktree 根执行，依赖本机 Swift / Xcode / xcodegen，无额外必填环境变量。单元测试与 UI 测试完整命令见 C1/C2/C3-REPORT.md；重新运行 UI 时替换为本机模拟器 ID，并使用新的 resultBundlePath。

```sh
rtk proxy bash tools/build-ipa.sh
```

脚本从自身位置确定仓库路径，并以当前代码提交命名新包。未推送仓库，未上传真实 WebDAV。待真机连接和签名恢复后，按 PLAN.md 第 3 节进行实际手感与系统授权验收。
