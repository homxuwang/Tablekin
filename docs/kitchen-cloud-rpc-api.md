# 家庭厨房云端接口 v2：本地联调依据

版本：2026-09-30。来源：用户转述的 WorkBuddy 云端部署和 authenticated 角色测试结果，以及本地代码核对。本文件不包含云端 SQL 源码。

## 库存事务

`adjust_stock_atomic(p_ingredient_id bigint, p_mode text, p_value numeric, p_reason text DEFAULT NULL, p_expected_stock numeric DEFAULT NULL, p_request_id text DEFAULT NULL) → jsonb`

- delta：p_value 为大于 0 的入库增量，锁内按当前库存增加。
- recount：p_value 为不小于 0 的实际库存，p_expected_stock 必填；与锁内库存不符时抛 stock_changed。
- 库存和流水同事务；不接收 owner_id、actor_id、order_id。
- 普通响应：`{ok,ingredient_id,ingredient_name,unit,mode,change,balance,balance_before,replayed:false}`。
- 重放响应：`{ok,ingredient_id,mode,change,balance,replayed:true}`；界面不依赖缺失的 name/unit/balance_before。
- 错误：not_signed_in、ingredient_not_found、not_kitchen_member、mode_invalid、value_invalid、expected_stock_required、stock_changed:<现库存>:<页面库存>、stock_negative、stock_too_large、no_change、request_id_reused。
- 重放的 balance 是原操作结果，可能早于最新库存，页面仍重新查询库存。

本地将待确认操作保存到按登录用户和厨房区分的 storage key，包含完整操作及幂等编号。超时后通过“重试确认”发送原操作，重新进入页面可恢复。有未确认操作时禁止发起新的库存写入，避免覆盖旧编号。明确拒绝的操作刷新后重新发起。

新建食材不能直写 stock，先插入初始 0 的食材，再以 recount(expected=0) 初始化。第二步失败时 API 携带已创建食材信息，页面恢复提交时的表单和 ID，避免重复创建；未确认的初始化使用 initial-<id> 编号核对。这两步不是服务端创建事务，不宣称失败时整条食材自动回滚。初始化期间关闭小程序后，应核对实际食材记录；未扩展云端原子创建食材接口。

## 邀请凭证

- `get_kitchen_invite(p_kitchen_id bigint) → {ok,kitchen_id,invite_code,created_at,rotated_at}`。
- `reset_kitchen_invite(p_kitchen_id bigint) → 上述字段及 rotated:true`。
- 仅拥有者可调用；kitchens.invite_code 已删除，厨房公开查询不再含邀请码。
- 错误：not_signed_in、kitchen_not_found、not_kitchen_owner、invite_code_conflict(reset)。
- 换码后旧链接不能加入，已有共有人不受影响。分享卡片可转发，拥有者可换码撤销旧链接。
- 未取得邀请码或换码处理中不可分享管理邀请；旧加载响应不能覆盖新码。换码响应不明时重新读取当前码。

## 日期与已读

- create_order_atomic 的 p_order_date 为就餐日期，允许北京时间今天至今天加 365 天，含端点。
- 错误：order_date_past、order_date_invalid、asap_requires_today、meal_time_invalid。
- asap 仅今天；时间按 HH:mm；range 的结束晚于开始，空结束表示开始之后。暂无跨午夜时间段。
- `mark_notifications_read(p_ids bigint[],p_kitchen_id bigint) → {marked}`：null/null 标本人全部，指定列表也只处理本人记录。本地空数组为无操作。

## owner_id 含义与权限

| 表 | owner_id 含义 | 操作人/创建者 | 权限依据 |
| --- | --- | --- | --- |
| kitchens | 厨房拥有者 | 当前会话创建 | 拥有者及厨房成员 |
| orders/order_items/shortage_alerts | 所属厨房拥有者 | diner_id 等业务字段 | 点菜人或厨房成员 |
| stock_logs | 所属厨房拥有者 | actor_id 为实际操作人 | 厨房成员 |
| categories/dishes/ingredients/dish_ingredients | 行创建者 | 当前会话创建 | 厨房成员关系；owner_id 不作为该批表的权限依据 |

四张业务表保留现有 owner_id 语义。后续收口菜单写入时如需重命名，可明确迁移为 created_by；不能仅凭 owner_id 判定共有人是否有管理权。

## 验证边界

WorkBuddy 回传已覆盖并发入库、接单与入库争用、盘点冲突、流水失败回滚、幂等重试、邀请隔离与换码、私密菜品读取和成员权限撤销。Codex 验证本地 API 和页面，没有独立执行这些云端测试。完整微信真机端到端流程仍需验证。
