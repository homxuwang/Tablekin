import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/availability.dart';
import '../utils/error_messages.dart';
import '../utils/meal_time.dart';
import '../widgets/common_widgets.dart';
import 'order_detail_screen.dart';

class CartScreen extends StatefulWidget {
  final int kitchenId;
  final String kitchenName;
  final List<Dish> dishes;
  final List<Ingredient> ingredients;
  final List<DishIngredient> recipes;

  const CartScreen({
    super.key,
    required this.kitchenId,
    required this.kitchenName,
    required this.dishes,
    required this.ingredients,
    required this.recipes,
  });

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  final _nameCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  DateTime _orderDate = DateTime.now();
  String _mealType = 'asap'; // asap | point | range
  String _timeStart = '18:30';
  String _timeEnd = '';
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = AppStateScope.read(context);
      _nameCtrl.text = state.dinerName.isNotEmpty
          ? state.dinerName
          : (state.currentUser?.displayName ?? '');
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  String get _orderDateStr => todayDateString(_orderDate);
  bool get _isToday => _orderDateStr == todayDateString();

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    DateTime temp = _orderDate;
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => Container(
        height: 280,
        color: AppColors.surface,
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                CupertinoButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
                CupertinoButton(
                  onPressed: () {
                    setState(() {
                      _orderDate = temp;
                      if (!_isToday && _mealType == 'asap') {
                        _mealType = 'point';
                      }
                    });
                    Navigator.pop(ctx);
                  },
                  child: const Text('确定', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            Expanded(
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.date,
                initialDateTime: _orderDate.isBefore(today) ? today : _orderDate,
                minimumDate: today,
                maximumDate: today.add(const Duration(days: 365)),
                onDateTimeChanged: (d) => temp = d,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickTime({required bool isEnd}) async {
    final initial = isEnd && _timeEnd.isNotEmpty ? _timeEnd : _timeStart;
    final parts = initial.split(':');
    final h = int.tryParse(parts.isNotEmpty ? parts[0] : '18') ?? 18;
    final m = int.tryParse(parts.length > 1 ? parts[1] : '30') ?? 30;
    DateTime temp = DateTime(2026, 1, 1, h, m);

    await showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => Container(
        height: 280,
        color: AppColors.surface,
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                CupertinoButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
                CupertinoButton(
                  onPressed: () {
                    final formatted =
                        '${temp.hour.toString().padLeft(2, '0')}:${temp.minute.toString().padLeft(2, '0')}';
                    setState(() {
                      if (isEnd) {
                        _timeEnd = formatted;
                      } else {
                        _timeStart = formatted;
                      }
                    });
                    Navigator.pop(ctx);
                  },
                  child: const Text('确定', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            Expanded(
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.time,
                use24hFormat: true,
                initialDateTime: temp,
                onDateTimeChanged: (d) => temp = d,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit(List<CartEntry> entries) async {
    final mealErr = validateMealSchedule(
      orderDate: _orderDateStr,
      mealTimeType: _mealType,
      start: _mealType == 'asap' ? null : _timeStart,
      end: _mealType == 'range' && _timeEnd.isNotEmpty ? _timeEnd : null,
    );
    if (mealErr != null) {
      setState(() => _error = mealErr);
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final state = AppStateScope.read(context);
      final name = _nameCtrl.text.trim();
      if (name.isNotEmpty) await state.setDinerName(name);
      final order = await state.backend.createOrder(
        kitchenId: widget.kitchenId,
        items: entries,
        dinerName: name.isEmpty ? '朋友' : name,
        note: _noteCtrl.text.trim(),
        orderDate: _orderDateStr,
        mealTimeType: _mealType,
        mealTimeStart: _mealType == 'asap' ? null : _timeStart,
        mealTimeEnd: _mealType == 'range' && _timeEnd.isNotEmpty ? _timeEnd : null,
      );
      state.clearCart(widget.kitchenId);
      await state.refreshBadges();
      if (!mounted) return;
      showAppToast(context, '已发给大厨，等着回话吧！');
      Navigator.of(context).pushReplacement(
        CupertinoPageRoute(builder: (_) => OrderDetailScreen(orderId: order.id)),
      );
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.of(context);
    final entries = state.cartEntries(widget.kitchenId);
    final total = state.cartTotalCount(widget.kitchenId);

    final wanted = {for (final e in entries) e.dish.id: e.count};
    final check = checkOrderAvailability(widget.dishes, widget.ingredients, widget.recipes, wanted);

    final mealLabel = mealScheduleText(
      orderDate: _orderDateStr,
      mealTimeType: _mealType,
      start: _timeStart,
      end: _timeEnd,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('点菜清单'),
        actions: [
          if (entries.isNotEmpty)
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              onPressed: () {
                state.clearCart(widget.kitchenId);
                Navigator.of(context).pop();
              },
              child: const Text('清空', style: TextStyle(color: AppColors.danger, fontSize: 15)),
            ),
        ],
      ),
      body: entries.isEmpty
          ? EmptyStateView(
              icon: CupertinoIcons.cart,
              title: '还没有点菜',
              subtitle: '回到菜单挑几道想吃的菜吧',
              action: GhostPillButton(label: '回菜单', onPressed: () => Navigator.of(context).pop()),
            )
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                    children: [
                      if (_error != null) InfoBanner(message: _error!),

                      AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.kitchenName,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 10),
                            for (var i = 0; i < entries.length; i++) ...[
                              if (i > 0) const Divider(),
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        entries[i].dish.name,
                                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                                      ),
                                    ),
                                    InlineCartStepper(
                                      count: entries[i].count,
                                      soldOut: false,
                                      onAdd: () => state.addToCart(widget.kitchenId, entries[i].dish),
                                      onRemove: () => state.decreaseFromCart(widget.kitchenId, entries[i].dish.id),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),

                      if (!check.ok) ...[
                        const SizedBox(height: 12),
                        AppCard(
                          color: AppColors.dangerBg,
                          border: Border.all(color: AppColors.dangerBorder),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '食材不够，请调整份数或提醒大厨补货',
                                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.danger),
                              ),
                              const SizedBox(height: 8),
                              ...check.problems.map(
                                (p) => Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Text(
                                    '• ${p.ingredientName}：需 ${p.needed}${p.unit}，剩 ${p.stock}${p.unit}${p.dishes.isNotEmpty ? '（${p.dishes}）' : ''}',
                                    style: const TextStyle(fontSize: 13, color: AppColors.danger),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              GhostPillButton(
                                label: '一键提醒大厨补货',
                                danger: true,
                                onPressed: () async {
                                  await state.backend.reportShortage(
                                    kitchenId: widget.kitchenId,
                                    dinerName: _nameCtrl.text.trim().isEmpty ? '朋友' : _nameCtrl.text.trim(),
                                    problems: check.problems,
                                  );
                                  if (context.mounted) showAppToast(context, '已发送缺料提醒给大厨');
                                },
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SectionHeader(title: '什么时候吃'),
                      AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            GestureDetector(
                              onTap: _pickDate,
                              child: Row(
                                children: [
                                  const Text('就餐日期', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                                  const Spacer(),
                                  Text(
                                    '${formatOrderDateLabel(_orderDateStr)}（$_orderDateStr）',
                                    style: const TextStyle(fontSize: 14.5, color: AppColors.primary, fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(CupertinoIcons.chevron_right, size: 15, color: AppColors.textMuted),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                            Wrap(
                              spacing: 8,
                              children: [
                                if (_isToday) _modeChip('尽快', 'asap'),
                                _modeChip('定个时间点', 'point'),
                                _modeChip('定个时间段', 'range'),
                              ],
                            ),
                            if (_mealType != 'asap') ...[
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  _timeBox(_timeStart, () => _pickTime(isEnd: false)),
                                  if (_mealType == 'range') ...[
                                    const Padding(
                                      padding: EdgeInsets.symmetric(horizontal: 10),
                                      child: Text('到', style: TextStyle(color: AppColors.textSecondary)),
                                    ),
                                    _timeBox(_timeEnd.isEmpty ? '不限' : _timeEnd, () => _pickTime(isEnd: true)),
                                    if (_timeEnd.isNotEmpty)
                                      CupertinoButton(
                                        padding: const EdgeInsets.only(left: 8),
                                        onPressed: () => setState(() => _timeEnd = ''),
                                        child: const Text('清除', style: TextStyle(fontSize: 13)),
                                      ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: quickMealTimes.map((t) {
                                  final on = _timeStart == t;
                                  return GestureDetector(
                                    onTap: () => setState(() => _timeStart = t),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: on ? AppColors.primaryLight : AppColors.surfaceSoft,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: on ? AppColors.primary : AppColors.border,
                                        ),
                                      ),
                                      child: Text(
                                        t,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                                          color: on ? AppColors.primary : AppColors.textSecondary,
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
                          ],
                        ),
                      ),

                      const SectionHeader(title: '给大厨留句话'),
                      AppCard(
                        child: Column(
                          children: [
                            TextField(
                              controller: _nameCtrl,
                              maxLength: 12,
                              decoration: const InputDecoration(
                                labelText: '你是谁',
                                hintText: '例如：阿明、妈妈',
                                counterText: '',
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _noteCtrl,
                              maxLines: 3,
                              maxLength: 200,
                              decoration: const InputDecoration(
                                labelText: '备注（选填）',
                                hintText: '少放辣、米饭两碗、不吃香菜…',
                                counterText: '',
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      GhostPillButton(
                        label: '复制点菜清单',
                        icon: CupertinoIcons.doc_on_doc,
                        onPressed: () {
                          final summary = [
                            '【${widget.kitchenName}】点菜清单',
                            ...entries.map((e) => '• ${e.dish.name} ×${e.count}'),
                            '想吃时间：$mealLabel',
                            if (_noteCtrl.text.trim().isNotEmpty) '备注：${_noteCtrl.text.trim()}',
                          ].join('\n');
                          Clipboard.setData(ClipboardData(text: summary));
                          showAppToast(context, '清单已复制到剪贴板');
                        },
                      ),
                    ],
                  ),
                ),

                // Sticky bottom submit bar
                Container(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
                  decoration: const BoxDecoration(
                    color: AppColors.surface,
                    border: Border(top: BorderSide(color: AppColors.border)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('共 $total 份', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                            Text('想吃：$mealLabel', style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 150,
                        child: PrimaryPillButton(
                          label: check.ok ? '发给大厨' : '食材不够',
                          loading: _submitting,
                          onPressed: check.ok ? () => _submit(entries) : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _modeChip(String label, String value) {
    final active = _mealType == value;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _mealType = value);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active ? AppColors.primary : AppColors.surfaceSoft,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: active ? AppColors.primary : AppColors.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: active ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _timeBox(String text, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceSoft,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      ),
    );
  }
}
