import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/error_messages.dart';
import '../utils/meal_time.dart';
import '../widgets/common_widgets.dart';

class IngredientsScreen extends StatefulWidget {
  final int kitchenId;

  const IngredientsScreen({super.key, required this.kitchenId});

  @override
  State<IngredientsScreen> createState() => _IngredientsScreenState();
}

class _IngredientsScreenState extends State<IngredientsScreen> {
  List<Ingredient> _list = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await AppStateScope.read(context).backend.fetchIngredients(widget.kitchenId);
      if (mounted) setState(() => _list = rows);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openEditor([Ingredient? existing]) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final unitCtrl = TextEditingController(text: existing?.unit ?? '克');
    final stockCtrl = TextEditingController(text: existing == null ? '0' : existing.stockText);
    final alertCtrl = TextEditingController(text: existing?.alertText ?? '0');

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        bool saving = false;
        String? localErr;
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                16,
                20,
                MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    existing == null ? '新增食材' : '编辑食材',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 14),
                  if (localErr != null) InfoBanner(message: localErr!),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: '食材名称', hintText: '例如：五花肉、鸡蛋'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: unitCtrl,
                    decoration: const InputDecoration(labelText: '单位', hintText: '克 / 个 / 盒 / 瓶'),
                  ),
                  if (existing == null) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: stockCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: '初始库存', hintText: '0'),
                    ),
                  ],
                  const SizedBox(height: 10),
                  TextField(
                    controller: alertCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: '低库存预警线（填 0 不提醒）',
                      hintText: '例如：200',
                    ),
                  ),
                  const SizedBox(height: 18),
                  PrimaryPillButton(
                    label: existing == null ? '添加食材' : '保存修改',
                    loading: saving,
                    onPressed: () async {
                      final name = nameCtrl.text.trim();
                      final unit = unitCtrl.text.trim();
                      if (name.isEmpty) {
                        setSheetState(() => localErr = '请输入食材名称');
                        return;
                      }
                      final initial = double.tryParse(stockCtrl.text.trim()) ?? 0;
                      final alert = double.tryParse(alertCtrl.text.trim()) ?? 0;
                      setSheetState(() {
                        saving = true;
                        localErr = null;
                      });
                      try {
                        final backend = AppStateScope.read(context).backend;
                        if (existing == null) {
                          await backend.createIngredient(
                            kitchenId: widget.kitchenId,
                            name: name,
                            unit: unit.isEmpty ? '份' : unit,
                            initialStock: initial,
                            alertThreshold: alert,
                          );
                        } else {
                          await backend.updateIngredient(
                            existing.id,
                            name: name,
                            unit: unit.isEmpty ? '份' : unit,
                            alertThreshold: alert,
                          );
                        }
                        if (ctx.mounted) Navigator.pop(ctx, true);
                      } catch (e) {
                        setSheetState(() {
                          saving = false;
                          localErr = friendlyError(e);
                        });
                      }
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (saved == true) {
      await _load();
      if (mounted) showAppToast(context, existing == null ? '食材已添加' : '食材已更新');
    }
  }

  Future<void> _adjustStock(Ingredient item, String mode) async {
    final isDelta = mode == 'delta';
    final valueCtrl = TextEditingController(text: isDelta ? '' : item.stockText);
    final reasonCtrl = TextEditingController();

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        bool busy = false;
        String? err;
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${isDelta ? '入库' : '盘点'} · ${item.name}',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '当前库存：${item.stockText}${item.unit}',
                    style: const TextStyle(fontSize: 13.5, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 14),
                  if (err != null) InfoBanner(message: err!),
                  TextField(
                    controller: valueCtrl,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: isDelta ? '本次新增数量（${item.unit}）' : '盘点后实际库存（${item.unit}）',
                      hintText: isDelta ? '例如：500' : '输入当前实际剩余量',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: reasonCtrl,
                    decoration: InputDecoration(
                      labelText: '备注（选填）',
                      hintText: isDelta ? '例如：超市补货' : '例如：冰箱清点',
                    ),
                  ),
                  const SizedBox(height: 18),
                  PrimaryPillButton(
                    label: isDelta ? '确认入库' : '确认盘点',
                    loading: busy,
                    onPressed: () async {
                      final val = double.tryParse(valueCtrl.text.trim());
                      if (val == null || val < 0 || (isDelta && val == 0)) {
                        setSheetState(() => err = '请输入有效数字');
                        return;
                      }
                      setSheetState(() {
                        busy = true;
                        err = null;
                      });
                      try {
                        await AppStateScope.read(context).backend.adjustStock(
                              ingredientId: item.id,
                              mode: mode,
                              value: val,
                              expectedStock: isDelta ? null : item.stock,
                              reason: reasonCtrl.text.trim(),
                            );
                        if (ctx.mounted) Navigator.pop(ctx, true);
                      } catch (e) {
                        setSheetState(() {
                          busy = false;
                          err = friendlyError(e);
                        });
                      }
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (ok == true) {
      await _load();
      if (mounted) showAppToast(context, isDelta ? '入库成功' : '盘点已更新');
    }
  }

  Future<void> _showLogs(Ingredient item) async {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return FutureBuilder<List<StockLog>>(
          future: AppStateScope.read(context).backend.fetchStockLogs(item.id),
          builder: (ctx, snap) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${item.name} · 库存明细',
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    if (snap.connectionState == ConnectionState.waiting)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CupertinoActivityIndicator()),
                      )
                    else if ((snap.data ?? const []).isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 28),
                        child: Center(
                          child: Text('还没有变动记录', style: TextStyle(color: AppColors.textMuted)),
                        ),
                      )
                    else
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: snap.data!.length,
                          separatorBuilder: (_, _) => const Divider(),
                          itemBuilder: (_, idx) {
                            final log = snap.data![idx];
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(log.reason, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500)),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${formatMonthDay(log.createdAt)} ${formatTimeHm(log.createdAt)}',
                                          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        '${log.changeText}${item.unit}',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: log.isPositive ? AppColors.doingText : AppColors.danger,
                                        ),
                                      ),
                                      Text(
                                        '${log.balanceText}${item.unit}',
                                        style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _deleteItem(Ingredient item) async {
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text('删除「${item.name}」？'),
        content: const Text('删除后菜品配方里关联的这项食材也会移除。'),
        actions: [
          CupertinoDialogAction(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await AppStateScope.read(context).backend.deleteIngredient(item.id);
      await _load();
      if (mounted) showAppToast(context, '已删除 ${item.name}');
    } catch (e) {
      if (mounted) showAppToast(context, friendlyError(e), isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lowItems = _list.where((e) => e.isLow).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('食材仓库'),
        actions: [
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            onPressed: () => _openEditor(),
            child: const Text('＋ 新增', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CupertinoActivityIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                children: [
                  if (_error != null) InfoBanner(message: _error!),
                  if (lowItems.isNotEmpty)
                    AppCard(
                      color: AppColors.waitBg,
                      border: Border.all(color: AppColors.primaryBorder),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '该补货了（${lowItems.length} 种）',
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.waitText,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: lowItems
                                .map(
                                  (i) => SmallTag(
                                    label: '${i.name} · ${i.stockText}${i.unit}',
                                    bg: Colors.white,
                                    fg: AppColors.waitText,
                                  ),
                                )
                                .toList(),
                          ),
                        ],
                      ),
                    ),
                  SectionHeader(title: '所有食材（${_list.length}）'),
                  if (_list.isEmpty)
                    EmptyStateView(
                      icon: CupertinoIcons.cube_box,
                      title: '还没有食材',
                      subtitle: '先添加常用食材，再挂到菜品配方里，系统会自动计算可做份数。',
                      action: PrimaryPillButton(
                        label: '＋ 新增食材',
                        onPressed: () => _openEditor(),
                      ),
                    )
                  else
                    ..._list.map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: AppCard(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      item.name,
                                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  Text(
                                    item.stockText,
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w700,
                                      color: item.isLow ? AppColors.danger : AppColors.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    item.unit,
                                    style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                                  ),
                                ],
                              ),
                              if (item.isLow) ...[
                                const SizedBox(height: 4),
                                Text(
                                  '低于预警线 ${item.alertText}${item.unit}，记得补货',
                                  style: const TextStyle(fontSize: 12.5, color: AppColors.danger),
                                ),
                              ],
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _actionChip('入库', primary: true, onTap: () => _adjustStock(item, 'delta')),
                                  _actionChip('盘点', onTap: () => _adjustStock(item, 'recount')),
                                  _actionChip('明细', onTap: () => _showLogs(item)),
                                  _actionChip('编辑', onTap: () => _openEditor(item)),
                                  _actionChip('删除', danger: true, onTap: () => _deleteItem(item)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _actionChip(String label, {bool primary = false, bool danger = false, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: primary
              ? AppColors.primaryLight
              : danger
                  ? AppColors.dangerBg
                  : AppColors.surfaceSoft,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: primary
                ? AppColors.primaryBorder
                : danger
                    ? AppColors.dangerBorder
                    : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: primary
                ? AppColors.primary
                : danger
                    ? AppColors.danger
                    : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
