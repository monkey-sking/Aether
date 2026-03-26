# Aether 邀请码与邀请奖励 MVP 方案

> 文档状态：`Planned`
> Workstream：`feature/referral-mvp`
> 说明：本文档基于当前代码里已经存在的 `referralCode` 试用入参能力，补齐最小可上线的邀请码闭环。它描述的是推荐实现，不代表当前已经上线。
> 当前代码基线：App 内已有“开始试用时可填写邀请码”的入口，但还没有“查看/分享邀请码、奖励记录、邀请统计”的完整体验。

## 1. 任务 intake baseline

- 目标用户：
  - 已开始试用或已付费的 Aether 用户，希望邀请朋友使用 Aether
  - 被邀请的新用户，希望在开始试用时获得明确好处
- 要解决的问题：
  - 当前 App 只支持“填邀请码”，但用户看不到自己的邀请码，也没有奖励反馈
  - 当前 Website 没有邀请入口，App 也没有邀请管理区，导致邀请码机制对普通用户不可见
- 期望用户可见结果：
  - 已有用户能在 App 里看到、复制并分享自己的邀请码
  - 新用户在开始试用时可输入邀请码并得到明确反馈
  - 邀请人能看到邀请成果和奖励时长
- 范围排除：
  - 不做复杂邀请活动页
  - 不做多层级分销、现金返佣、优惠券叠加
  - 不做复杂风控后台或人工审核台
  - 不在第一版解决跨设备深链自动带码安装
- 优先级：`Medium-High`
- 依赖：
  - Admin 侧能持久化邀请码、邀请关系和奖励时长
  - App 侧 About / License Management 可增加一个邀请奖励区块
  - Website 至少能承载邀请规则文案；第一版可不做自动带码
- 预期发布目标：
  - 首个商业化口径稳定后的激活/试用闭环版本
  - 若需要更具体发布批次，当前建议挂到“商业模型定稿后的首个 stable 商业版本”

## 2. 当前现状

### 2.1 已有能力

- App 在试用入口里已经有“邀请码（可选）”输入框
- App 开始试用时会把 `referralCode` 发到 `/trial/start`
- 后端若返回 `referralCode`，App 会保存到本地 entitlement 状态

### 2.2 缺失能力

- 用户无法查看自己的邀请码
- 用户无法一键复制或分享邀请码
- 用户无法知道邀请码是否被使用
- 用户无法看到自己获得了多少奖励时长
- 官网没有邀请入口或邀请规则说明
- 没有最小反作弊规则定义

## 3. 推荐 MVP 决策

以下是推荐默认值，除非你明确要求改动，否则本文档后续内容按这些值展开。

### 3.1 奖励触发点

- 推荐：`被邀请人成功开始试用` 时立即结算

原因：

- 现有闭环里最稳定、最早发生的可验证动作就是 `/trial/start`
- 比“等付费后再奖励”更容易让普通用户理解，也更容易让邀请码字段产生真实转化

### 3.2 奖励对象

- 推荐：`邀请人和被邀请人都获得奖励`

原因：

- 只有邀请人获益时，被邀请人输入邀请码的动机偏弱
- 双边奖励更符合“邀请码”而不是“内部运营码”的用户预期

### 3.3 奖励单位

- 推荐：双方各 `+3 天` 试用 / 使用时长奖励

说明：

- 当前 Aether 公开口径里已经有 trial-first 商业模型
- `+3 天` 足够可感知，但不会像 `+7 天` 那样明显放大奖励滥用空间

### 3.4 上限与去重

- 每个新账户只能使用 `1` 个邀请码
- 同一邀请关系只奖励 `1` 次
- 单个邀请人的累计奖励上限推荐先设为 `30 天`
- 同邮箱自邀直接拒绝
- 同 `deviceId` 重复刷码直接拒绝

### 3.5 第一版入口

- App：必须做
- Admin：必须做
- Website：第一版只做文案和 FAQ，不要求做深链自动带码

## 4. 用户故事

### 4.1 邀请人

- 作为一个已经能用 Aether 的用户，我希望在 App 里看到自己的邀请码，并一键复制给别人
- 作为一个邀请人，我希望知道已经有多少人成功用了我的邀请码，以及我累计多拿了多少天

### 4.2 被邀请人

- 作为一个新用户，我希望知道输入邀请码后我会得到什么
- 作为一个新用户，我希望在开始试用后立刻看到邀请码是否生效，而不是猜

### 4.3 运营 / 支持

- 作为支持人员，我希望能查到邀请码归属、使用记录和奖励结果，便于排查争议

## 5. 产品范围

### 5.1 App 范围

- 在 About -> Manage License 中新增“邀请奖励”区块
- 对已激活或试用中的用户显示：
  - 我的邀请码
  - 复制邀请码
  - 复制邀请文案
  - 已邀请人数
  - 已获得奖励天数
  - 最近邀请记录
- 对未激活用户保留现有“邀请码（可选）”输入框
- 在开始试用成功后显示邀请码是否生效

### 5.2 Admin 范围

- 为每个账户生成稳定邀请码
- 接受 `/trial/start` 中传入的 `referralCode`
- 结算邀请奖励
- 提供邀请码摘要和最近记录给 App
- 提供支持排查所需的最小后台查询能力

### 5.3 Website 范围

- 在 Pricing / FAQ / Download 文案中补充“邀请码可带来额外试用时长”的说明
- 可选：增加一个简短 FAQ，说明邀请码应在 App 内开始试用时填写

### 5.4 明确不做

- 不做单独邀请中心网页
- 不做社交裂变任务系统
- 不做排行榜
- 不做邀请码批量生成器
- 不做带渠道归因的复杂营销分析

## 6. 体验设计

以下设计判断以当前 Aether App 内的 About / License Management 结构为基线，是本地推荐方案，不是竞品对标结论。

### 6.1 邀请人入口

- 入口位置：`About -> Manage License`
- 显示条件：`trialing` 或 `active`
- 放置位置：授权状态摘要下方，设备列表上方

推荐信息结构：

1. 标题：`邀请好友`
2. 副文案：`对方开始试用后，你和对方都会多 3 天。`
3. 主体内容：
   - `我的邀请码`
   - `AETHER-AB12`
   - `复制邀请码`
   - `复制邀请文案`
4. 结果摘要：
   - `已邀请 4 人`
   - `累计奖励 12 天`
5. 最近记录：
   - `m***@gmail.com · 已奖励 +3 天`
   - `y***@icloud.com · 试用已开始`

### 6.2 被邀请人入口

- 保持当前试用表单中的邀请码输入框
- 在输入框下增加短帮助文案：
  - `有好友的邀请码？填入后你们都会获得额外试用时长。`

### 6.3 成功反馈

- 开始试用成功且邀请码生效：
  - `试用已开始。邀请码已生效，你已获得额外 3 天。`
- 开始试用成功但邀请码无效：
  - `试用已开始，但邀请码未生效。请检查后重试。`
- 邀请人刷新后看到：
  - `已有 1 位好友开始试用，你获得了 +3 天。`

### 6.4 普通用户文案原则

- 不向普通用户暴露 `referral`, `invite attribution`, `entitlement mutation` 这类内部术语
- 普通用户只看见：
  - 邀请码
  - 额外天数
  - 是否生效
  - 最近邀请结果

## 7. App UI 草图

```text
+------------------------------------------------------+
| Aether Trial Active                                  |
| Trial until Apr 20, 2026                             |
+------------------------------------------------------+
| 邀请好友                                              |
| 对方开始试用后，你和对方都会多 3 天。                  |
|                                                      |
| 我的邀请码                                           |
| AETHER-AB12                                          |
| [复制邀请码] [复制邀请文案]                           |
|                                                      |
| 已邀请 4 人        累计奖励 12 天                     |
|                                                      |
| 最近邀请                                             |
| m***@gmail.com  已奖励 +3 天                          |
| y***@icloud.com  已开始试用                           |
+------------------------------------------------------+
| Devices                                              |
| ...                                                  |
+------------------------------------------------------+
```

## 8. API 草案

API 命名可按 Admin 项目现有风格调整。这里优先保持和当前 App 的 `POST JSON` 风格一致。

### 8.1 扩展 `POST /trial/start`

请求：

```json
{
  "email": "new-user@example.com",
  "deviceId": "install-123",
  "appId": "com.7fei.Aether",
  "channel": "stable",
  "deviceModel": "MacBook Pro",
  "osVersion": "macOS 15.x",
  "appVersion": "1.0.0",
  "referralCode": "AETHER-AB12"
}
```

响应新增字段建议：

```json
{
  "status": "trialing",
  "licenseKey": "XXXX-YYYY",
  "trialEndsAt": "2026-04-20T00:00:00Z",
  "referralCode": "AETHER-Z9Q2",
  "referralApplied": true,
  "referralRewardDays": 3,
  "message": "Trial started. Referral applied."
}
```

字段说明：

- `referralApplied`: 邀请码是否成功生效
- `referralRewardDays`: 本次给当前用户增加了多少天
- `referralCode`: 当前账户自己的邀请码，供后续 App 展示

### 8.2 扩展 `POST /verify`

请求维持现有 `credentialBody()` 结构。

响应新增字段建议：

```json
{
  "status": "trialing",
  "plan": "trial",
  "trialEndsAt": "2026-04-20T00:00:00Z",
  "devicesUsed": 1,
  "maxDevices": 1,
  "referralCode": "AETHER-Z9Q2",
  "referralSummary": {
    "rewardDaysTotal": 12,
    "successfulReferrals": 4,
    "rewardDaysCap": 30,
    "recentEvents": [
      {
        "eventId": "evt_001",
        "inviteeMaskedEmail": "m***@gmail.com",
        "status": "rewarded",
        "rewardDays": 3,
        "occurredAt": "2026-03-26T09:00:00Z"
      }
    ]
  }
}
```

### 8.3 新增 `POST /referral/summary`

用途：

- App 邀请区块的显式刷新
- 降低把所有邀请明细都塞进 `/verify` 的耦合

请求：

```json
{
  "email": "owner@example.com",
  "licenseKey": "XXXX-YYYY",
  "deviceId": "install-123",
  "appId": "com.7fei.Aether"
}
```

响应：

```json
{
  "referralCode": "AETHER-Z9Q2",
  "rewardDaysTotal": 12,
  "successfulReferrals": 4,
  "rewardDaysCap": 30,
  "recentEvents": [
    {
      "eventId": "evt_001",
      "inviteeMaskedEmail": "m***@gmail.com",
      "status": "rewarded",
      "rewardDays": 3,
      "occurredAt": "2026-03-26T09:00:00Z"
    }
  ]
}
```

### 8.4 错误码建议

- `referral_invalid`
- `referral_self_not_allowed`
- `referral_already_used`
- `referral_same_device_not_allowed`
- `referral_reward_cap_reached`

App 应把这些错误翻译成普通用户能懂的提示，不直接展示原始错误码。

## 9. 数据模型建议

最小数据结构建议：

- `accounts`
  - `account_id`
  - `email`
  - `referral_code`
- `referral_events`
  - `event_id`
  - `inviter_account_id`
  - `invitee_account_id`
  - `invitee_email`
  - `invitee_device_id`
  - `status`
  - `reward_days_inviter`
  - `reward_days_invitee`
  - `occurred_at`
- `reward_ledger`
  - `ledger_id`
  - `account_id`
  - `reason`
  - `delta_days`
  - `related_event_id`
  - `created_at`

## 10. 风险与约束

### 10.1 滥用风险

- 同一人多个邮箱刷奖励
- 同一设备反复换邮箱
- 公开传播邀请码导致运营成本不可控

### 10.2 MVP 级缓解

- 同邮箱自邀禁止
- 同设备重复领奖励禁止
- 账户累计奖励上限 30 天
- 只记录最近 N 条邀请记录给 App 展示

### 10.3 暂不解决

- IP 风控
- 支付后回滚奖励
- 团队邀请码 / 渠道邀请码并存

## 11. 验收标准

### 11.1 App

- `trialing` 或 `active` 用户能在 About 里看到自己的邀请码
- 用户可以一键复制邀请码
- 用户可以一键复制邀请文案
- 试用表单里继续支持输入邀请码
- 输入有效邀请码并开始试用后，用户能看到明确的奖励结果提示

### 11.2 Admin

- 新账户创建后可以稳定得到一个邀请码
- `/trial/start` 能识别、校验并结算邀请码
- `/verify` 或 `/referral/summary` 能返回邀请码摘要
- 同邮箱自邀、同设备重复领奖励都能被拒绝

### 11.3 Website

- FAQ 或 Pricing 至少有一处向普通用户说明邀请码奖励机制

## 12. 测试建议

- 正常路径：A 邀请 B，B 成功开始试用，双方各得 +3 天
- 无邀请码路径：B 不填邀请码，试用正常开始
- 非法邀请码：B 输入不存在的邀请码，试用可开始但邀请码不生效
- 自邀路径：A 用自己的邀请码开始另一台设备试用，应拒绝奖励
- 重复路径：同一个新账户重复使用邀请码，不应重复结算

## 13. 发布与回滚

### 13.1 发布前输入

- 奖励天数最终拍板
- 奖励上限最终拍板
- Admin 支持查询方式准备好
- Website 文案准备好

### 13.2 回滚路径

- 若发现奖励逻辑异常，Admin 侧先关闭 referral reward 开关
- App 继续显示邀请码输入框，但服务端不再结算奖励
- 若 App 邀请区块已上线，可保留展示但标记“邀请奖励暂不可用”

## 14. 推荐拆分的后续 workstreams

- `feature/referral-admin`
  - 负责邀请码生成、关系绑定、奖励结算、summary API
- `feature/referral-app-ui`
  - 负责 About 邀请区块、复制操作、试用成功反馈
- `feature/referral-website-copy`
  - 负责官网 FAQ / Pricing / Download 文案
- `review/referral-abuse-rules`
  - 负责风控边界与支持排查口径

## 15. 待确认决策

以下决策会改变实现方向，建议在开始正式编码前拍板：

1. 奖励天数最终是 `+3`、`+5` 还是 `+7`
2. 奖励对象是否双边都奖励
3. 奖励上限是否按生命周期累计，还是按月封顶
4. Website 第一版是否需要带 `?ref=` 的活动页，还是只保留 App 内手动填码
