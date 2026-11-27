const Map<String, String> _rpcErrors = {
  'sort_kind_invalid': '排序类型不正确，请重新进入',
  'sort_items_invalid': '排序项目有变化，请刷新列表后重试',
  'sort_conflict': '其他成员已调整顺序或增删项目，请刷新后重新排序',
  'not_signed_in': '请先登录后再操作',
  'kitchen_not_found': '这个厨房不存在了，换一个试试吧',
  'kitchen_not_visible': '这是个私密厨房，需要请主厨发送邀请码',
  'kitchen_name_required': '请先给厨房起个名字',
  'kitchen_name_too_long': '厨房名字有点长，30 个字以内就好',
  'order_items_required': '还没有点菜，先挑几道吧',
  'order_too_many_items': '一次点得太多了，分两单发吧',
  'order_item_invalid': '这一单里有认不出来的菜，回菜单重新选一下',
  'dish_not_in_kitchen': '有道菜不属于这个厨房，回菜单重新选一下',
  'quantity_invalid': '份数不太对，请重新填一下',
  'order_not_found': '这一单找不到了，可能已经被撤回',
  'not_kitchen_member': '你不是这个厨房的成员，做不了这个操作',
  'order_not_pending': '这一单已经处理过了，刷新看看最新状态',
  'order_already_accepted': '大厨已经接单了，这时候撤不了，跟大厨说一声吧',
  'order_not_accepted': '这一单还没接单，不能标记出餐',
  'order_not_cancelable': '这一单现在的状态不能撤回',
  'diner_only': '只有点这一单的人才能撤回',
  'meal_time_invalid': '就餐时间没填对，请重新选一下',
  'ingredient_missing': '这一单要用到的某个食材已被删除，补一下再试',
  'kitchen_not_owner': '只有厨房拥有者能做这个操作',
  'not_kitchen_owner': '只有厨房拥有者能做这个操作',
  'ingredient_not_found': '这份食材不存在或已删除，请刷新库存',
  'order_date_past': '就餐日期不能早于今天',
  'order_date_invalid': '请选择有效的就餐日期（最多预约未来 365 天）',
  'asap_requires_today': '「尽快」只能用在今天，预约其他日期请选时间',
  'value_invalid': '请输入有效的数字',
  'mode_invalid': '库存操作类型不对，请重试',
  'expected_stock_required': '盘点前请先查看当前库存',
  'no_change': '库存没有变化',
  'stock_negative': '库存不能为负数',
  'stock_too_large': '数量太大了，分几次记吧',
  'request_id_reused': '这次操作编号已用过，请重新发起',
  'invite_code_conflict': '邀请码生成冲突，请再试一次',
  'invite_code_not_found': '邀请码无效或已失效，请向朋友要一个新的',
};

String friendlyError(Object error) {
  final raw = error.toString().replaceFirst(RegExp(r'^Exception:\s*'), '').trim();
  final firstLine = raw.split('\n').first.trim();
  final parts = firstLine.split(':');
  final head = parts.first.trim();

  if (head == 'ingredient_shortage' && parts.length >= 4) {
    return '「${parts[1]}」不够：需要 ${parts[3]}，只剩 ${parts[2]}，先去食材仓库补一下库存。';
  }
  if (head == 'dish_not_orderable') {
    final name = parts.skip(1).join(':').trim();
    return name.isNotEmpty ? '「$name」今天点不了，换一道试试' : '这道菜今天点不了';
  }
  if (head == 'stock_changed' && parts.length >= 3) {
    return '这份库存刚被更新：现在实际是 ${parts[1]}，页面上看到的是 ${parts[2]}，刷新后再盘点。';
  }
  if (_rpcErrors.containsKey(head)) {
    return _rpcErrors[head]!;
  }
  for (final entry in _rpcErrors.entries) {
    if (firstLine.contains(entry.key)) {
      return entry.value;
    }
  }
  if (firstLine.contains('SocketException') || firstLine.contains('Failed host lookup')) {
    return '网络连接不可用，请检查网络后重试';
  }
  return firstLine.isEmpty ? '操作失败，请稍后重试' : firstLine;
}
