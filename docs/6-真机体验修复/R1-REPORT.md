# 轮次 6 R1 返修报告

起点 8235d2fe2；固定 Kotlin 2bdd3c58b。没有子代理、push 或真实 WebDAV 写入。日志均位于 `.build/round6/`，编译失败不作为业务红灯，UI 执行 0 项不计通过。最终全量回归须在最后提交后执行。

## 单元记录

### F1：完成，提交见本单元 Git 记录
ReaderStyleStore.swift 的路径前缀为 App/Sources/Features/Reader/。`ReaderStyleStore.swift:32` 跳过回退加载的偏好覆盖，`:190` 先在同一 backup_files 存储保留原字节，使用毫秒时间与 UUID 防止同名覆盖；保存失败继续阻止写回。部分导入回退也备份输入。测试为 `tools/appcore-check/Tests/ReaderAdvancedCheckTests/ReaderInterfaceConfigTests.swift:8`。
红灯 r1-f1-red3.log，断言 testFallbackPreservesOriginalBytesBeforeSelectionAndEditing：`Executed 1 test, with 8 failures`；绿灯 r1-f1-green2.log：`Executed 10 tests, with 0 failures`；UI r1-f1-ui.log：`Executed 1 test, with 0 failures`。r1-f1-red/red2 的编译错误为测试接线错误，不计红灯。

## 真机验收清单
安装前提：手机旧版标识为 com.starlitxiling.legado.ios，覆盖包须使用该标识及有效描述文件；不改 App/project.yml，不能直接安装默认标识包。
F1：恢复损坏或部分损坏阅读样式，进入阅读、选择并修改样式；阅读可用，加载回退不改变原阅读偏好，存储保留 broken 备份原文。
