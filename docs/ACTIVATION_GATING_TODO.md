# Activation Gating Status + Remaining TODO

> 文档状态：`Planned + Source-synced`
> Workstream：`fix/activation-gating-regression`
> 说明：这份文档最初是从 0 到 1 的实施规划。2026-03-28 已按当前代码回写，现阶段它记录的是“已落地基线 + 剩余验证/收口”，不再代表功能尚未开始。

## 当前代码基线

已在本地源码中确认：

- 已有统一门禁状态源：`AboutCenter.swift` 中的 `AetherEntitlementGateState`
- 已有 root 分流：`ActivationGateView.swift` 里的 `AetherRootView` 会在锁定态显示 `ActivationGateView`，在 `active / trialing` 或离线宽限态显示 `AetherMainView`
- 已有 runtime gating：`AetherApp.swift` 会在未解锁时阻止语音意图执行、听写/命令执行、头控执行、快捷键面板打开等核心行为
- 已有冷启动 / 刷新处理：`loading` 状态、离线 snapshot、7 天 offline grace 已在 `AboutCenter.swift` 中实现
- 已有设备数恢复路径：`/devices` 与 `/devices/remove` 的拉取/移除逻辑已经落地

当前没有在本地代码里看到单独的“Resend Activation”动作入口；如果产品仍要求它，这部分仍属于 gap。

## 已落地项

- [x] 共享 entitlement gate model
- [x] 锁定态 root experience
- [x] 主窗口与核心 runtime gating
- [x] 冷启动加载态与 offline grace 基线
- [x] device-limit 基础恢复路径

## 仍待完成

### 1. 回归验证
- [ ] 新安装、无授权：确认始终进入锁定页，且不能旁路使用核心能力
- [ ] 开始试用 / 激活成功：确认 root 切换、runtime 放行、HUD/面板状态都同步恢复
- [ ] 过期 / inactive：确认重新锁定，不会短暂露出可用态
- [ ] device limit reached：确认锁定态里设备管理路径可真正恢复，而不是只显示信息
- [ ] offline grace：确认断网校验失败时宽限放行和文案都符合预期

### 2. 恢复路径补齐
- [ ] 如果产品仍需要“重发激活码 / resend activation”，补一个明确入口；当前本地代码未看到这条路径

### 3. 交互与边界收口
- [ ] 检查 `loading -> unlocked`、`loading -> locked`、`offline grace -> refresh success/fail` 的 UI 切换是否足够稳定
- [ ] 检查 About / update channel / update check 在锁定态下是否仍保持可恢复、可解释

## 关键代码位置

- [ActivationGateView.swift](/Volumes/SSD/Projects/Aether/App/Apps/AetherCore/ActivationGateView.swift)
- [AboutCenter.swift](/Volumes/SSD/Projects/Aether/App/Apps/AetherCore/AboutCenter.swift)
- [AetherApp.swift](/Volumes/SSD/Projects/Aether/App/Apps/AetherCore/AetherApp.swift)

## 当前判断

原先“Activation state is currently mostly informational / app does not currently gate core features”这一结论已不成立。更准确的状态是：

- 门禁功能已落地到 root 和 runtime
- 当前剩余工作以回归验证、恢复路径补齐、边界稳定性收口为主
