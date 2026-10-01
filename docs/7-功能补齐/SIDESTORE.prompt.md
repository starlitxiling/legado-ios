<subagent_contract>
你在帮用户把 iOS 版「阅读」(Legado) 改为通过 SideStore 侧载，以便手机自行续签免费 Apple ID 的 7 天签名。你可以操作用户的 Mac 和 iPhone。必须遵守：
1. 任何时候都不要读取、输入、记录或回显用户的 Apple ID 密码、双重认证验证码或锁屏密码；遇到需要这些的界面，停下来请用户亲自输入，等用户说完成再继续。
2. 不要删除手机上现有的「阅读」App，直到第 4 步数据核对通过且用户明确同意。
3. 不要修改仓库代码，不要 commit 或 push；只允许运行下面写明的构建脚本。
4. 每一步完成后简短汇报实际看到的结果（界面文字、命令输出末尾）；失败就原样报告错误并停下，不要猜测或跳步。
5. 最后一条消息结论先行：哪些步骤完成、哪些未完成及原因、用户还需要做什么。
</subagent_contract>

<task>
## 背景
- 仓库 iOS worktree：/Users/xiling/Work/legado-ios/.claude/worktrees/ios（分支 ios，提交 fc378743b）。
- 手机：iPhone 16，iOS 18.6.2，设备名「夕灵的iPhone」。用户不会升级系统。
- 现有「阅读」是用 Xcode 以包标识 com.starlitxiling.legado.ios 安装的，签名 2026-10-06 过期。
- SideStore 用免费账号安装导入的 IPA 时会在包标识后追加团队 ID，因此会装出一个新的「阅读」，与现有 App 数据不互通，需要通过备份迁移。用户已知晓并同意。
- 官方安装文档：https://docs.sidestore.io/docs/installation/prerequisites 与 https://docs.sidestore.io/docs/installation/install 。界面文字以实际看到的为准；若与本任务书不符，以官方文档和实际界面为准并在汇报中说明差异。

## 第 0 步：准备安装包
1. 检查 `dist/Legado-1.0-fc378743b.ipa` 是否存在（在上述 worktree 根目录下）。
2. 若不存在：在 worktree 根目录运行 `bash tools/build-ipa.sh`，等待完成，确认 `dist/` 下生成以当前提交短哈希命名的 IPA。该 IPA 未签名，由 SideStore 签名。
3. 汇报 IPA 路径与大小。

## 第 1 步：手机安装 LocalDevVPN
1. 在 iPhone 的 App Store 搜索并安装「LocalDevVPN」。
2. 打开它并连接；出现「允许添加 VPN 配置」时点允许，需要锁屏密码时请用户输入。
3. 确认显示已连接。

## 第 2 步：Mac 用 iloader 安装 SideStore
1. 从 iloader 的官方 GitHub Releases（以 SideStore 文档链接为准）下载 macOS DMG 并安装。
2. 用数据线连接 iPhone；若手机提示「信任此电脑」，点信任（锁屏密码由用户输入）。
3. 打开 iloader，点「Sign in with your Apple Account」，请用户亲自登录 Apple ID（必须与以后在 SideStore 里登录的是同一个）。
4. 选择设备「夕灵的iPhone」，点「Install SideStore (Stable)」，等待完成并汇报结果。
5. 手机上：
   - 「设置 → 隐私与安全性 → 开发者模式」确认已开启（未开启则开启，会重启）。
   - 「设置 → 通用 → VPN 与设备管理」，在开发者 App 下信任该 Apple ID。

## 第 3 步：配置 SideStore
1. 确认 LocalDevVPN 已连接。
2. 打开 SideStore，请用户用同一个 Apple ID 登录。
3. 进入「My Apps」，点 SideStore 旁的「7 DAYS」续签一次；出现证书相关提示选「Yes」或「Refresh Now」。汇报续签后的剩余天数。

## 第 4 步：迁移数据并安装新「阅读」
1. 在**现有**「阅读」里做备份：「我的 → 备份与恢复」，优先「备份」到已配置的 WebDAV；若 WebDAV 不可用，用本地备份导出到「文件」App。记下备份文件名。
2. 把第 0 步的 IPA 传到手机（AirDrop 或存到「文件」App），在 SideStore「My Apps」点「+」选择该 IPA 安装。汇报安装结果及新 App 的名称。
3. 打开新装的「阅读」，从第 1 小步的备份恢复（WebDAV：「我的 → 备份与恢复 → 恢复」，需要时请用户填写 WebDAV 账号与应用密码；本地：选择该备份文件）。
4. 核对新「阅读」与旧「阅读」：书架书籍数量、任选两本书的阅读进度、书源数量、阅读样式。汇报两边的数字是否一致。
5. 一致后询问用户是否删除旧的「阅读」（Xcode 安装的那个）；用户同意才删除。

## 第 5 步：确认续签可用
1. 在 SideStore「My Apps」确认「阅读」和 SideStore 都显示剩余天数（应约为 7 天）。
2. 查看 SideStore 设置中是否有后台自动续签选项，如有则开启，并汇报其名称和状态。
3. 告诉用户日常做法：每 7 天内保持 LocalDevVPN 连接并打开 SideStore 点「7 DAYS」续签；免费账号最多同时 3 个侧载 App（SideStore 与阅读占 2 个）。

## 交付
最后一条消息（不超过 400 字）：每一步的状态（完成 / 未完成及原因）、新「阅读」的版本与剩余天数、数据核对结果、用户还需要亲自完成的事项。
</task>
