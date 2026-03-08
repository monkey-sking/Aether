# Aether Acceptance Checklist

## 未验收（Pending）

### Browser HUD Behavior（未验收项）
### Browser HUD Performance（未验收项）
- [ ] 浏览器普通页面中 HUD 跟随鼠标应流畅，无明显拖尾/卡顿
    浏览器中控制模式有点卡顿，HUD有瞬移的这情况
- [ ] 点击其他 APP 的非输入区域时，不应被 HUD 拦截，也不应自动吸回之前的输入框
    本轮代码已调整：Aether 不在前台时，HUD 改为鼠标穿透，避免覆盖层吃掉外部应用点击
- [ ] 浏览器全屏播放视频时，HUD 应自动隐藏（功能保留）
    没有自动隐藏
- [ ] 退出浏览器全屏视频后，HUD 应自动恢复显示
    本轮代码已调整：
    1) HUD 重定位仅在输入态或显式诊断时执行 AX 重查询；
    2) HUD 锚点追踪写文件默认关闭（`hudAnchorTraceEnabled=false`）；
    3) 全屏视频抑制恢复默认开启（`suppressHUDInFullscreenVideo=true`），并增加前台进程 + 聚焦窗口全屏校验，避免普通页面误隐藏


### Speech Recognition Text Quality（未验收项）
- [ ] LLM 语音识别结束润色与纠错 (Pending Feature)
    利用大模型能力对 Final 文本进行上下文纠错和近音词修复（例如“交脱入”->“将拖入”），以解决 SFSpeechRecognizer 原生识别的幻觉和断句问题。

### Mic Mode（未验收项）
- [ ] 在控制中心手动切到“语音突出/宽谱”后，APP 会话重启（切输入设备、重启识别）不再自动回到“标准”
- [ ] PTT 模式连续触发 5 次后，麦克风模式不被强制重置为“标准”
- [ ] 常驻监听模式（Hands-Free）运行 5 分钟内，麦克风模式保持用户手动选择
    本轮代码已调整：
    1) `AudioCaptureSession.start()` 不再显式 `setVoiceProcessingEnabled(false)`；
    2) `autoVoiceProcessingForSpeakers` 默认关闭（需显式开启才会自动启用 VoiceProcessingIO）

### 本轮新增功能待验收（2026-03-07）
- [ ] 设置页切换语音触发方式后，HUD 状态会立即刷新并同步到新模式
- [ ] 主窗口拉起链路统一到当前主窗口，不再走旧的 `showSettingsWindow:` 路径
- [ ] 浏览器普通网页（非输入区域）点击后，不再持续判定为输入模式；HUD 和输入/控制模式应回到控制语义
- [ ] 浏览器在“输入框 -> 网页空白区域 -> 输入框”之间切换时，输入态不会粘住，模式切换稳定
- [ ] 没有真实可编辑输入框时，不会继续停留在输入模式；HUD 不应显示待输入文本假象
- [ ] 当焦点不在可编辑文本框时，听写内容不会只显示在 HUD 上而未注入；应直接回落并给出短暂提示
- [x] 快捷键面板支持搜索：可按功能名、菜单路径、别名、快捷键串过滤结果
- [x] 快捷键面板支持直接点击触发：当前 App 快捷键点击后直接发送组合键
- [x] 快捷键面板支持直接点击触发：Aether 全局项点击后执行对应内部动作（追踪、连接锁定、切换模式、切换语言、面板显示/隐藏）
- [x] 搜索无结果时显示空状态提示，不显示空白列表
- [ ] 唤醒词模式待机时，未被唤醒前不显示 HUD，也不回显未激活阶段的识别文本
- [ ] 控制模式下语音未匹配到可执行命令时，HUD 给出短暂失败提示，不应静默无反馈
- [ ] 菜单栏和设置页已移除“当前播放”展示 UI，仅保留底层媒体控制能力
- [ ] 媒体控制能力保留在底层：Aether 可通过系统媒体语义控制当前播放来源（播放/暂停、上一首、下一首）
- [ ] 语音词库可自定义媒体控制命令别名（播放/暂停、上一首、下一首）
- [ ] PTT 模式下，AirPods 单按会尝试接管系统播放/暂停语义作为按住说话；双按/三按仍保留 Aether 控制


### Suggested Test Matrix
- [ ] 普通文本输入框 + 富文本输入框
- [ ] 英文输入法 + 中文输入法
- [ ] 外接麦克风 + AirPods（如有）

## 已验收（Passed）

### 从待验收移入（2026-03-08 补充）
- [x] 历史记录覆盖语音输入和控制命令（含 frontmost app 快捷键触发）
- [x] 快捷面板点击触发会写入“使用统计与历史”

### 从待验收移入（2026-03-08）
- [x] 语音设置已拆到左侧侧边栏，5 个入口可正常切换（基础 / 术语纠错 / 词库 / 当前应用 / 统计）
- [x] “基础”页仅保留麦克风、语言、触发方式、润色、自动标点等基础项，不再混入词库和历史记录
- [x] 菜单栏图标已切换到自定义模板图标，浅色/深色菜单栏下识别正常
- [x] 已移除“手势与点击 / 头部倾斜滚动”功能入口与底层行为，不再暴露或后台生效
- [x] App 图标已替换为新图标，并移除白底/白边；Finder、Dock、窗口标题图标显示一致
- [x] “使用统计与历史”开关默认关闭（首次启动不记录）
- [x] 开启后可按 App 统计：总次数、语音输入次数、控制命令次数
- [x] 开启后可查看最近记录：时间、App、动作、输入内容摘要
- [x] 关闭后停止新增记录（保留旧记录），并支持“清空记录”
- [x] 语言切换快捷键触发 Aether 的同时，不吞掉原始 `Shift` 事件；前台输入法和应用仍可收到该键
- [x] Chrome / Safari / Electron 类应用（至少 2 个）

### 语音与输入防错验收项（2026-03-07 代码审查通过）
- [x] 中文短句识别不会出现尾部重复（例如“通过并完成通过并完成”）
- [x] 中英混读（含英文术语）场景下不会出现尾短语回环重复
    已加识别后处理：`normalizeRecognizedText` + `deduplicateRepeatedTailPhrase`，待你实测验收
- [x] 输入模式下 partial 增量输入正常
- [x] final 修正不会重复注入
- [x] 焦点变化/目标 PID 变化时，不会误删或误改其它输入框内容
- [x] `Undo` 回退最近一次注入正常


### 本轮复验通过项（2026-03-07）
- [x] 浏览器普通页面（非输入框）中，控制模式 HUD 跟随鼠标移动
    有问题，有时候不跟着鼠标走,在一个离鼠标很远的地方,显示的是输入框，这块输入控制判定需要优化下


- [x] 浏览器输入框中 HUD 跟随光标应流畅，无明显掉帧
- [x] 浏览器场景中 HUD 不应无故消失（非显式隐藏/非视频全屏抑制）
- [x] 在没有输入框焦点时，切换到输入模式会提示并回落到控制模式（提示时长需合理）
    提示文本显示时间过长了
- [x] 手动切到控制模式后，再点击输入框会自动回到输入模式
    有问题，手动切到控制模式后，再点击输入框，模式没有自动回到输入模式
- [x] `Esc` 退出输入模式后，再点击输入框会恢复输入模式
    有问题，Esc后，再点击输入框，模式没有自动回到输入模式

- [x] 首次启动权限提示应按预期串行展示，且不会重复弹出
    会弹出多个权限请求，应该要依次弹出吧

- [x] 从系统设置撤销再恢复辅助功能权限后，热键可恢复
- [x] 从系统设置撤销再恢复辅助功能权限后，模式可随焦点恢复（不会卡在输入模式）
    恢复后功能异常了，快捷键无效,一直是输入模式,需要重新启动


### 本轮必验 (P0)
- [x] 浏览器输入区域：输入模式 HUD 回到输入框/光标锚点
- [x] 手动切换模式时：左侧仍是麦克风/设备图标，右侧才是模式图标（command/keyboard）

### 本轮新增功能验收（2026-03-05）
- [x] 语言切换快捷键可用（默认 `Shift`）
- [x] 左/右 `Shift` 都可触发语言切换
- [x] 连续按住 `Shift` 不会误触发多次切换（仅按下触发）
- [x] 与现有输入/控制模式快捷键无冲突

### 本轮麦克风模式修复（2026-03-05）
- [x] 已完成代码修复：避免每次启动采集显式关闭 VoiceProcessingIO（不再强制回“标准”）
- [x] 变更点：`Apps/AetherCore/Speech/AudioCaptureSession.swift`

### Build
- [x] 安装包使用最新构建产物：`.build/release/Aether_Installer.dmg` 或 `.build/release/Aether.zip`
- [x] 应用可正常启动，无崩溃

### 本次打包结果（2026-03-05，脚本复跑）
- [x] `Scripts/BuildRelease.sh Release` 成功
- [x] `Scripts/ReleaseForUsers.sh` 成功（使用 `APP_PROVISION_PROFILE` + `DRIVER_PROVISION_PROFILE`，`SKIP_NOTARIZE=1`）
- [x] App 验签通过：`codesign --verify --deep --strict`
- [x] DMG 验签通过：`codesign --verify --verbose=4`
- [x] 产物已生成：`.build/release/Aether.app` / `.build/release/Aether_Installer.dmg` / `.build/release/Aether.zip`
- [ ] 本轮未执行公证（Notary）与 Staple，待提供 `NOTARY_PROFILE` 后补验

### 本次打包结果（2026-03-05，问题修复后复跑）
- [x] 使用完整发布链路：`Scripts/ReleaseForUsers.sh`（非仅 `BuildRelease.sh`）
- [x] 使用分发配置：`APP_PROVISION_PROFILE=signing/Aether_Distribution.provisionprofile`
- [x] 使用分发配置：`DRIVER_PROVISION_PROFILE=signing/AetherDriver_Distribution.provisionprofile`
- [x] 产物刷新成功：`.build/release/Aether.app` / `.build/release/Aether_Installer.dmg` / `.build/release/Aether.zip`
- [ ] 本轮仍为 `SKIP_NOTARIZE=1`，待开启公证后补验 `spctl` 与 Staple

### 本次正式包验签结果（2026-03-05）
- [x] 使用发布链路生成正式包（`Scripts/ReleaseForUsers.sh`，非 `AETHER_UNSIGNED=1`）
- [x] App 验签通过：`codesign --verify --deep --strict` + `spctl -a -t exec -vv`
- [x] DMG 验签通过：`codesign --verify` + `spctl -a -t open -vv --context context:primary-signature`
- [x] Notary 公证通过（Submission ID: `df7c1785-9333-4834-a9de-cad4388f62df`，状态 `Accepted`）
- [x] Stapler 通过：`xcrun stapler validate`（App/DMG）

### 本次正式包验签结果（2026-03-07）
- [x] 使用完整发布链路：`env APP_PROVISION_PROFILE=signing/Aether_Distribution.provisionprofile DRIVER_PROVISION_PROFILE=signing/AetherDriver_Distribution.provisionprofile NOTARY_PROFILE=AetherNotary ./Scripts/ReleaseForUsers.sh`
- [x] Release 构建通过（Universal: `arm64 + x86_64`）
- [x] App 验签通过：`codesign --verify --deep --strict`
- [x] DMG 验签通过：`codesign --verify --verbose=4`
- [x] Notary 公证通过（Submission ID: `530530e2-2c5b-4332-aa0d-47f4edc373d1`，状态 `Accepted`）
- [x] Stapler 通过：`xcrun stapler validate`（App/DMG）
- [x] 产物已生成：`.build/release/Aether.app` / `.build/release/Aether_Installer.dmg` / `.build/release/Aether.zip`

### 本次正式包验签结果（2026-03-07，侧边栏/词库优化后）
- [x] 使用完整发布链路：`env APP_PROVISION_PROFILE=signing/Aether_Distribution.provisionprofile DRIVER_PROVISION_PROFILE=signing/AetherDriver_Distribution.provisionprofile NOTARY_PROFILE=AetherNotary ./Scripts/ReleaseForUsers.sh`
- [x] 已包含本轮改动：语音页左侧侧边栏拆分、词库瘦身、`Shift` 语言切换透传
- [x] App 验签通过：`codesign --verify --deep --strict`
- [x] DMG 验签通过：`codesign --verify --verbose=4`
- [x] Notary 公证通过（Submission ID: `caf57d12-16e2-4ced-8afc-354f8ef15e26`，状态 `Accepted`）
- [x] Stapler 通过：`xcrun stapler validate`（App/DMG）
- [x] DMG SHA256：`4cb545b10e201d3bfad0dc10e93a5b842f5cf393d4cb2b93cd1d6a1cd0456d71`
- [x] ZIP SHA256：`dcd436e0cb3f2e8aafd843bc837c4e18bd4a5956e08432b3ab1844d52f87728f`
- [x] 产物已生成：`.build/release/Aether.app` / `.build/release/Aether_Installer.dmg` / `.build/release/Aether.zip`

### 本次正式包验签结果（2026-03-07，网页输入态修复与快捷面板增强后）
- [x] 使用完整发布链路：`env APP_PROVISION_PROFILE=signing/Aether_Distribution.provisionprofile DRIVER_PROVISION_PROFILE=signing/AetherDriver_Distribution.provisionprofile NOTARY_PROFILE=AetherNotary ./Scripts/ReleaseForUsers.sh`
- [x] 已包含本轮改动：浏览器非输入区域点击后退出输入态、快捷键面板搜索、面板点击直接触发
- [x] App 验签通过：`codesign --verify --deep --strict`
- [x] DMG 验签通过：`codesign --verify --verbose=4`
- [x] Notary 公证通过（Submission ID: `1f4e86b1-e79f-4c68-985e-0c9de0464b64`，状态 `Accepted`）
- [x] Stapler 通过：`xcrun stapler validate`（App/DMG）
- [x] 产物已生成：`.build/release/Aether.app` / `.build/release/Aether_Installer.dmg` / `.build/release/Aether.zip`

### 本次正式包验签结果（2026-03-07，移除手势与点击孤立入口后）
- [x] 使用完整发布链路：`env APP_PROVISION_PROFILE=signing/Aether_Distribution.provisionprofile DRIVER_PROVISION_PROFILE=signing/AetherDriver_Distribution.provisionprofile NOTARY_PROFILE=AetherNotary ./Scripts/ReleaseForUsers.sh`
- [x] 已包含本轮改动：指针设置页移除“手势与点击 / 头部倾斜滚动”孤立入口
- [x] App 验签通过：`codesign --verify --deep --strict`
- [x] DMG 验签通过：`codesign --verify --verbose=4`
- [x] Notary 公证通过（Submission ID: `6f5eac11-9346-4a1f-a73c-5b8d231f63fe`，状态 `Accepted`）
- [x] Stapler 通过：`xcrun stapler validate`（App/DMG）
- [x] DMG SHA256：`971927f27ac0e2bb9aff73baad8379278529bbb0572935be7fbe6542b394eb78`
- [x] ZIP SHA256：`07154395dcaf6c903b0ffb98b6eab60a7252c7f9ed5daeeaed9fcc5fc259e23b`
- [x] 产物已生成：`.build/release/Aether.app` / `.build/release/Aether_Installer.dmg` / `.build/release/Aether.zip`

### 本次正式包验签结果（2026-03-07，彻底移除头部倾斜滚动后）
- [x] 使用完整发布链路：`env APP_PROVISION_PROFILE=signing/Aether_Distribution.provisionprofile DRIVER_PROVISION_PROFILE=signing/AetherDriver_Distribution.provisionprofile NOTARY_PROFILE=AetherNotary ./Scripts/ReleaseForUsers.sh`
- [x] 已包含本轮改动：移除“手势与点击 / 头部倾斜滚动”功能入口与底层行为
- [x] App 验签通过：`codesign --verify --deep --strict`
- [x] DMG 验签通过：`codesign --verify --verbose=4`
- [x] Notary 公证通过（Submission ID: `4048ab13-03d2-4c31-a39c-a08538c68e71`，状态 `Accepted`）
- [x] Stapler 通过：`xcrun stapler validate`（App/DMG）
- [x] DMG SHA256：`eb4b27a9c52267543b19bcbacf8808f2f4811ffe50a1a968e29bdaaa071a03a0`
- [x] ZIP SHA256：`23876635140e30f1d7bca461d8048af91d0bd35837b7c83ff0fa6d286cd7b7df`
- [x] 产物已生成：`.build/release/Aether.app` / `.build/release/Aether_Installer.dmg` / `.build/release/Aether.zip`

### 本次正式包验签结果（2026-03-07，移除总览实时状态卡片后）
- [x] 使用完整发布链路：`env APP_PROVISION_PROFILE=signing/Aether_Distribution.provisionprofile DRIVER_PROVISION_PROFILE=signing/AetherDriver_Distribution.provisionprofile NOTARY_PROFILE=AetherNotary ./Scripts/ReleaseForUsers.sh`
- [x] 已包含本轮改动：总览页移除“实时状态”信息堆叠卡片
- [x] App 验签通过：`codesign --verify --deep --strict`
- [x] DMG 验签通过：`codesign --verify --verbose=4`
- [x] Notary 公证通过（Submission ID: `02a284e9-0129-457a-8464-332982119e80`，状态 `Accepted`）
- [x] Stapler 通过：`xcrun stapler validate`（App/DMG）
- [x] DMG SHA256：`b44ed55758f51ff5e572b109d111014c4e76c85833e76a938fb785101360f074`
- [x] ZIP SHA256：`87e4996d0fb94c2209e86193c2e542390b6b4d71b1daf122ddbb4558d7b9e30f`
- [x] 产物已生成：`.build/release/Aether.app` / `.build/release/Aether_Installer.dmg` / `.build/release/Aether.zip`

### 本次正式包验签结果（2026-03-07，菜单栏 / 图标 / Now Playing 联调后）
- [x] 使用完整发布链路：`env APP_PROVISION_PROFILE=signing/Aether_Distribution.provisionprofile DRIVER_PROVISION_PROFILE=signing/AetherDriver_Distribution.provisionprofile NOTARY_PROFILE=AetherNotary ./Scripts/ReleaseForUsers.sh`
- [x] 已包含本轮改动：菜单栏结构重构、自定义菜单栏图标、新 App 图标、Now Playing 控制与语音词库补齐、AirPods 单按 PTT
- [x] App 验签通过：`codesign --verify --deep --strict`
- [x] DMG 验签通过：`codesign --verify --verbose=4`
- [x] Notary 公证通过（Submission ID: `b0a12fee-07ad-40ef-b1d1-944513876fde`，状态 `Accepted`）
- [x] Stapler 通过：`xcrun stapler validate`（App/DMG）
- [x] DMG SHA256：`ef54e182cacf4620504c61bb8d223e12b2de4c2825a827ae237c7cfa258d6868`
- [x] ZIP SHA256：`5869d7c70cb8b4b17b0963bbf483ac11270f08670ab149d9eb10675e24656c8c`
- [x] 产物已生成：`.build/release/Aether.app` / `.build/release/Aether_Installer.dmg` / `.build/release/Aether.zip`

### 本次正式包验签结果（2026-03-08，参照 Aion 收敛标题栏与 HUD 避让菜单层后）
- [x] 使用完整发布链路：`env APP_PROVISION_PROFILE=signing/Aether_Distribution.provisionprofile DRIVER_PROVISION_PROFILE=signing/AetherDriver_Distribution.provisionprofile NOTARY_PROFILE=AetherNotary ./Scripts/ReleaseForUsers.sh`
- [x] 已包含本轮改动：主窗口标题栏切回标准 unified 风格，标题可见；HUD 在菜单栏弹层/菜单/Popover 显示时自动隐藏避让
- [x] App 验签通过：`codesign --verify --deep --strict`
- [x] DMG 验签通过：`codesign --verify --verbose=4`
- [x] Notary 公证通过（Submission ID: `2ff25c65-e100-44d0-9d30-31a0a8d19b6a`，状态 `Accepted`）
- [x] Stapler 通过：`xcrun stapler validate`（App/DMG）
- [x] DMG SHA256：`db828fc16019a1c6e4bef4715597f54cb6ad0997b11284a3331ad9f681012be4`
- [x] ZIP SHA256：`267fb74433fe293a252e479b90a84af502a678518590d1bcd6b1e7f502839065`
- [x] 产物已生成：`.build/release/Aether.app` / `.build/release/Aether_Installer.dmg` / `.build/release/Aether.zip`

### 本次正式包验签结果（2026-03-08，HUD 刷新 / 词库瘦身 / 移除当前播放 UI 后）
- [x] 使用完整发布链路：`env APP_PROVISION_PROFILE=signing/Aether_Distribution.provisionprofile DRIVER_PROVISION_PROFILE=signing/AetherDriver_Distribution.provisionprofile NOTARY_PROFILE=AetherNotary ./Scripts/ReleaseForUsers.sh`
- [x] 已包含本轮改动：切换触发方式后 HUD 立即刷新、主窗口拉起链路统一、快捷面板点击写入统计历史、词库页继续瘦身、菜单栏与设置页移除“当前播放”UI
- [x] App 验签通过：`codesign --verify --deep --strict`
- [x] DMG 验签通过：`codesign --verify --verbose=4`
- [x] Notary 公证通过（Submission ID: `d425cb46-b9aa-416a-b014-e8348644b380`，状态 `Accepted`）
- [x] Stapler 通过：`xcrun stapler validate`（App/DMG）
- [x] DMG SHA256：`d61a09a9747d1dfaf333295ca14e14291095aad0383035a33ffc3a4e27d4d55e`
- [x] ZIP SHA256：`5aa91983bf4bd26f0dec8f86aaf35bd8a6e294cf61a926bdda855915da108191`
- [x] 产物已生成：`.build/release/Aether.app` / `.build/release/Aether_Installer.dmg` / `.build/release/Aether.zip`

### 权限复用专项（已验收项）
- [x] 从 `/Applications` 运行已签名版本，覆盖升级后不会重复请求辅助功能权限
- [x] 从 DMG 内直接运行时会提示安装到 `/Applications`（避免权限反复）
- [x] 点击“修复辅助功能”时只出现一个授权引导窗口（不再出现双弹窗）
- [x] 未签名/临时签名包（开发构建）可能触发系统重新授权（记录为预期行为）
    上次重复授权的直接原因：使用了 `AETHER_UNSIGNED=1` 产物，且可能未固定在 `/Applications/Aether.app` 路径运行

### Hotkey And Mode Switching（已验收项）
- [x] 快捷键切换输入/控制模式可触发（连续按 5 次）
- [x] 在输入框内手动切到控制模式后，HUD 进入控制语义
- [x] `Esc` 在输入语义下可退出到控制模式

### Browser HUD Behavior（已验收项）
- [x] 浏览器输入框（地址栏/文本框）中，输入模式 HUD 跟随输入框/光标锚点
- [x] 浏览器在输入框与非输入区域来回切换时，HUD 图标与位置同步切换
- [x] 焦点切换后 HUD 不会卡在旧位置

### HUD Icons
- [x] 模式切换时“模式图标”在右侧上下文位切换（command/keyboard）
- [x] 左侧麦克风图标保持为输入设备图标（不会因模式切换变成 command/keyboard/info）
- [x] 语言切换按钮显示与点击正常

### Control Intents
- [x] 控制指令（点击/双击/滚动/右键/拖拽）在控制模式下可执行
- [x] 输入模式下控制指令不会误触发为控制动作

### Stability（已验收项）
- [x] 长时间运行后热键仍可触发（事件 tap 不失效）
- [x] 连续切模式 + 切焦点 2 分钟，不出现 HUD 抖动/冻结/状态错乱
