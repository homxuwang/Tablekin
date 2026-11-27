# 发给 WorkBuddy：菜单和分类排序接口

## 当前真机报错，请优先修复

用户保存分类顺序时返回：

```text
Could not find the function public.reorder_kitchen_items(p_expected_ids, p_ids, p_kind, p_kitchen_id) in the schema cache
```

这表示当前请求环境的 PostgREST 没有解析到可调用的对应函数，不是前端拖动算法报错。请先核对实际连接的项目/数据库，再检查 public 中是否已部署函数、参数名字和类型是否完全符合下方签名、authenticated 是否有 EXECUTE 权限。错误中参数按字母排列是正常现象，不需要为此改变调用顺序。

如果函数缺失，请按以下事务协议实施；若只有其他名字或参数签名的函数，请提供兼容本协议的入口，避免直接覆盖本地前端。若实际函数与权限都正确，再按平台支持方式刷新 PostgREST schema cache，并用真实 authenticated 会话调用验证。

请回传函数实际定义/参数、授权、真实角色调用结果。应验证分类与菜品保存、非法ID拒绝、多人冲突，以及相同目标重试成功；不要仅以“SQL执行成功”作为完成。此轮前端只修正显示与错误翻译，没有执行云端迁移。

本地已增加厨房管理→分类/菜品「调整顺序」，支持长按拖动、边缘自动滚动、置顶/置底、预览后保存。2026-10-21 按用户要求改为管理页原位置展开，不再跳转独立排序页；云端协议不变。请保留本地代码并实现以下云端接口。需要先部署云端，再上传新体验版。

## 接口协议

```sql
reorder_kitchen_items(
  p_kitchen_id bigint,
  p_kind text,              -- 仅 categories 或 dishes
  p_ids bigint[],           -- 调整后的该厨房完整ID列表
  p_expected_ids bigint[]   -- 打开排序页时的完整ID顺序，用于冲突检测
) returns jsonb
```

成功返回 `{"ok":true,"kind":"dishes","ordered_ids":[3,1,2],"noop":false}`。
当前顺序已经与 p_ids 相同时返回同样结构且 noop=true，支持服务端已保存但响应丢失后的安全重试。

## 事务与权限

1. 基于实际表结构检查 categories/dishes.sort_order 类型、可空性及现有写入权限。使用现有字段，不需要新增永久置顶标记。
2. 函数 SECURITY DEFINER，固定 search_path，身份取 auth.uid()，不接受 owner_id/user_id。撤销 PUBLIC/anon EXECUTE，仅 authenticated 可执行。
3. 校验登录、厨房存在和当前用户是拥有者/共有人。拒绝非成员，包括能浏览公开厨房的顾客。不要改变四张业务表 owner_id 创建者语义。
4. 同一厨房排序串行化（例如锁 kitchens 行），再按固定 ID 顺序锁待排序业务行。必须在获得锁后重新读真实顺序并判断；同一事务完成全部更新。
5. 顺序统一为 sort_order ASC NULLS LAST, id ASC，与现有前端读取一致。p_kind 只能是白名单，不将未经验证的字符串拼接为SQL。
6. p_ids 与 p_expected_ids 必须是一维、下标从1开始、无NULL、无重复的正ID数组；两者集合一致，且恰好覆盖该厨房目标表全部记录（包括未公开/下架项目）。不可接受其他厨房ID或只排部分列表。
7. 先核对 p_ids 集合和完整性，再判断当前顺序是否已等于 p_ids（是则安全重试成功）；否则当前完整顺序必须等于 p_expected_ids，不相等返回 sort_conflict，不覆盖他人修改。
8. 按 p_ids 的位置一次更新 sort_order=0..N-1。不可修改 kitchen_id、category_id、owner_id 等其他字段。一条更新失败应全部回滚。
9. 检查并发新增/删除与排序的相互影响，锁和查询必须保证按事务实际快照校验；必要时统一相关写入口的锁协议。验证两名成员同时排序时一个成功、另一个冲突或目标已一致。

菜品排序是厨房全局顺序；顾客选择分类时保留该分类菜品的相对顺序。分类排序只改变分类栏。置顶指移动到第一位，不是永久锁定在顶部。

## 错误码

- not_signed_in
- kitchen_not_found
- not_kitchen_member
- sort_kind_invalid
- sort_items_invalid：重复/无效/跨厨房ID等非法参数
- sort_conflict：原顺序或项目集合变化，要求刷新后重排

前端已映射中文错误。接口不存在会提示排序服务尚未上线，不会退回客户端逐条写入。

## 验证与回传

- 使用真实 authenticated 角色分别验证拥有者、共有人成功和顾客拒绝。
- 分类和菜品拖动/置顶后的顺序重读正确，顾客页面按相同字段显示。
- 非法kind、跨厨房ID、重复ID、NULL元素、异常数组、遗漏项目全部拒绝。
- 两个成员基于同一原顺序保存不同结果时，后者不能覆盖前者；相同目标重试成功且不重复改变顺序。
- 任一更新失败整体回滚；菜品所属分类、图片、标签等不变。
- 提供函数签名、授权、真实角色测试结果；不要删除真实数据。

本地前端验证覆盖移动算法、触摸换位与取消、迟到测量回调、成员限制、失败保留草稿、防止重复保存，以及RPC参数。实际云端与微信触摸效果仍需联调。
