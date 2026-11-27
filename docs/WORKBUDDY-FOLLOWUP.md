# WorkBuddy 云端补充请求：已回传

2026-09-30，用户已回传本文件所列库存事务、邀请码隔离和私密菜品权限均已部署，由 WorkBuddy 使用 authenticated 角色实测。Codex 已核对本地新接口并补齐重试、错误提示和日期边界；云端实测结果来源于用户报告。

当前决策：categories、dishes、ingredients、dish_ingredients 的 owner_id 保留行创建者语义，权限继续基于厨房成员关系。stock_logs.owner_id 为厨房拥有者，actor_id 为实际操作人。详细联调协议见 [kitchen-cloud-rpc-api.md](kitchen-cloud-rpc-api.md)。

以下为历史请求留档，描述的是修改前的问题，不表示这些问题仍未处理。

本地已保留你实现的订单 RPC，补齐了就餐日期选择、站内提醒、状态自动刷新和拥有者入口。以下两项云端问题需进一步处理，不能仅通过前端隐藏按钮或刷新解决。

## 1. 手动库存必须与接单使用同一套事务约束

当前 `utils/api.js` 的 `adjustStock` 仍然“读取 stock → 写绝对 stock → 单独插 stock_logs”。例如读取 100 后接单扣为 80，前端入库 +10 写入 110，会覆盖接单扣库，正确余额应是 90；流水写入失败也不会回滚库存。

请新增并验证以下 RPC（这是建议协议，部署后请回传最终协议，当前前端尚未调用它）：

`adjust_stock_atomic(p_ingredient_id bigint, p_mode text, p_value numeric, p_reason text, p_expected_stock numeric) → jsonb`

- 身份从会话取得，校验食材存在、属于当前用户参与的厨房。
- `p_mode='delta'` 用于入库：锁定食材，在锁内按当前库存增加 p_value。
- `p_mode='recount'` 用于盘点：p_value 为实际库存绝对值，p_expected_stock 为用户盘点前页面看到的值。在锁内核对 expected；不一致抛 `stock_changed` 让用户刷新确认，避免用陈旧页面 delta 覆盖接单扣库。
- 禁止负余额、非法数值，更新库存和写流水必须在一个事务内；与 accept_order_atomic 的食材锁兼容。
- 可加入请求幂等键（若加入，请提供参数名），用于响应丢失后的重试去重。
- `stock_logs.owner_id` 统一存厨房拥有者。新增 `actor_id` 记录实际操作人；接单扣库和手动入库/盘点都在服务端取当前会话身份写 actor，不接受客户端指定身份。
- 库存数值及库存流水的客户端直接写入口需要收紧，同时保留名称、单位等普通编辑；新建食材初始化库存为 0，库存变动走事务接口。请提供权限实测，不能只依赖前端调用约定。
- 返回建议 `{ok:true, ingredient_id, balance, change}`，并提供全部错误码。测试入库与接单并发、两人入库并发、旧库存盘点、流水失败回滚和重试。

## 2. 邀请码不能随公开厨房行返回

当前前端厨房查询使用 SELECT *，`fetchMyKitchens` 也显式查询 invite_code。按此前 kitchens_read 策略，普通用户能读公开厨房行。请用普通已登录顾客身份确认是否拿得到 invite_code；若能，顾客可调用 join_kitchen_by_code 成为共有人并取得管理权限。

- 将邀请码存放在只允许拥有者读取的受限表，或通过拥有者专用 RPC 获取；普通厨房查询不得返回可用于加入管理成员的凭证。
- 建议提供 `get_kitchen_invite(p_kitchen_id bigint) → {invite_code}`，只允许拥有者调用；需要配合前端查询字段同步修改。
- 移出成员后如需撤销旧链接，应提供重置邀请码能力；明确当前分享卡片是否允许转发加入。
- 不要只在 RLS 中限制厨房行或隐藏 UI，必须测试普通顾客无法读取邀请凭证、无法自行生成凭证，拥有者仍可分享有效邀请。
- 本地已将邀请区和厨房资料修改入口限制为拥有者，但这只是交互约束，不代表云端漏洞已修复。

## 联调确认

- `p_order_date` 现在取用户选定的就餐日期，按北京时间定义今天。请确认服务端接受未来日期并校验真实日期、不得早于今天；asap 仅适用于今天；range 的结束须晚于开始，空结束允许“开始之后”。
- 确认 `mark_notifications_read(p_ids:null,p_kitchen_id:null)` 只标记当前用户全部提醒，单条 ID 列表仍逐条校验本人。
- 使用顾客、拥有者、共有人三个真实会话验证新订单提醒分别落到拥有者和共有人；顾客状态更新可读，移出成员后权限立即撤销。
- 检查私密厨房的公开菜品是否仍可能被跨厨房搜索返回；菜品公开必须同时满足厨房可访问，不能只判断 dishes.is_public。

请先回传以上新增接口的准确参数、返回示例、错误码及权限结果，再同步关闭会影响当前前端的旧入口。订单已有 RPC 协议继续保持不变。
