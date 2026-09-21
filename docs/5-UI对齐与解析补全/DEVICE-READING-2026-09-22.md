# 真机验收状态（2026-09-22）

按用户最新指示，轮次 5 的中期与最终 iPhone 测试暂缓。本轮没有向已连接 iPhone 安装应用、恢复备份或执行阅读测试。不能报告真机整架更新成功率、内存峰值，也不能用模拟器结果替代这些指标。

已完成的模拟器证据：本地书十格式导入末章、阅读器界面与交互、设置/书源编辑、真实 WebBook 四流程 7/8。最终构建结果及日志索引见 SUMMARY.md。

恢复真机验证时需执行 PLAN.md §5.3：恢复用户备份，整架刷新并与 14/47 基线比较，验证本地书全格式和阅读器操作，测量内存峰值是否不超过 300 MB。WebDAV 现有凭据仅有读取授权。

Android 侧 `adb devices -l` 无设备，本机无 Android SDK/emulator/AVD。备份导出/导入与字段兼容已有离线测试，但 Android 应用恢复和逐屏并排截图尚未完成，保留为外部验收缺口。

尝试从 Google 官方下载 Android 命令行工具，`dl.google.com` 与 `dl.google.cn` 均返回 `curl: (35) LibreSSL SSL_connect: SSL_ERROR_SYSCALL`，未取得安装文件。本机剩余磁盘约 13 GiB。未安装 SDK、未运行 Android 模拟器；互导验收保持未完成。下载入口来自 [Android Developers](https://developer.android.com/studio)。

改用 Python urllib/SSL 请求官方主站仍返回 `SSL: UNEXPECTED_EOF_WHILE_READING`，未取得文件；问题不限于 curl 的 LibreSSL 客户端。
