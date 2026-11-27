import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/error_messages.dart';
import '../utils/meal_time.dart';
import '../widgets/common_widgets.dart';
import 'menu_screen.dart';

class OrderDetailScreen extends StatefulWidget {
  final int orderId;

  const OrderDetailScreen({super.key, required this.orderId});

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  KitchenOrder? _order;
  bool _isChef = false;
  bool _loading = true;
  bool _busy = false;
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
      final backend = AppStateScope.read(context).backend;
      final order = await backend.fetchOrder(widget.orderId);
      bool isChef = false;
      if (order != null) {
        final myKitchens = await backend.fetchMyKitchens();
        isChef = myKitchens.any((k) => k.id == order.kitchenId);
      }
      if (!mounted) return;
      setState(() {
        _order = order;
        _isChef = isChef;
      });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _runAction(Future<void> Function() action, String successMsg) async {
    final state = AppStateScope.read(context);
    setState(() => _busy = true);
    try {
      await action();
      await state.refreshBadges();
      await _load();
      if (mounted) showAppToast(context, successMsg);
    } catch (e) {
      if (mounted) showAppToast(context, friendlyError(e), isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _accept() async {
    setState(() => _busy = true);
    try {
      final res = await AppStateScope.read(context).backend.acceptOrder(widget.orderId);
      if (!mounted) return;
      if (!res.ok) {
        final msg = res.problems.map((p) => '${p.ingredientName} 不足（需 ${p.needed}，剩 ${p.stock}）').join('\n');
        showCupertinoDialog<void>(
          context: context,
          builder: (ctx) => CupertinoAlertDialog(
            title: const Text('食材不够，暂时无法接单'),
            content: Text(msg),
            actions: [
              CupertinoDialogAction(onPressed: () => Navigator.pop(ctx), child: const Text('知道了')),
            ],
          ),
        );
      } else {
        await AppStateScope.read(context).refreshBadges();
        await _load();
        if (mounted) showAppToast(context, '已接单，库存已自动扣减');
      }
    } catch (e) {
      if (mounted) showAppToast(context, friendlyError(e), isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    final ctrl = TextEditingController();
    final reason = await showCupertinoDialog<String>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('这单做不了'),
        content: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: CupertinoTextField(
            controller: ctrl,
            placeholder: '给点菜人留句话（选填），如：今天没买到排骨',
          ),
        ),
        actions: [
          CupertinoDialogAction(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('确认回复'),
          ),
        ],
      ),
    );
    if (reason == null || !mounted) return;
    await _runAction(
      () => AppStateScope.read(context).backend.rejectOrder(widget.orderId, reason: reason),
      '已回复点菜人',
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.of(context);
    final order = _order;
    final isMine = order != null && order.dinerId == state.currentUser?.id;

    return Scaffold(
      appBar: AppBar(title: const Text('订单详情')),
      body: _loading
          ? const Center(child: CupertinoActivityIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(16), child: InfoBanner(message: _error!)))
              : order == null
                  ? const EmptyStateView(icon: CupertinoIcons.doc_text, title: '找不到这一单')
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                        children: [
                          AppCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    StatusPill(status: order.statusInfo),
                                    const Spacer(),
                                    Text(
                                      '#${order.id}',
                                      style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                _infoRow('厨房', order.kitchenName.isEmpty ? '厨房' : order.kitchenName),
                                _infoRow('点菜人', order.dinerName),
                                _infoRow(
                                  '想吃时间',
                                  mealScheduleText(
                                    orderDate: order.orderDate,
                                    mealTimeType: order.mealTimeType,
                                    start: order.mealTimeStart,
                                    end: order.mealTimeEnd,
                                  ),
                                ),
                                _infoRow('下单时间', '${formatMonthDay(order.createdAt)} ${formatTimeHm(order.createdAt)}'),
                                if (order.note.isNotEmpty) ...[
                                  const Divider(height: 20),
                                  Text('备注：${order.note}', style: const TextStyle(fontSize: 14, color: AppColors.textPrimary)),
                                ],
                                if (order.rejectReason.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    '大厨回复：${order.rejectReason}',
                                    style: const TextStyle(fontSize: 14, color: AppColors.danger, fontWeight: FontWeight.w500),
                                  ),
                                ],
                              ],
                            ),
                          ),

                          SectionHeader(title: '${order.items.length} 道菜 · 共 ${order.totalPortions} 份'),
                          AppCard(
                            child: Column(
                              children: [
                                for (var i = 0; i < order.items.length; i++) ...[
                                  if (i > 0) const Divider(height: 18),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          order.items[i].dishName,
                                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                                        ),
                                      ),
                                      Text(
                                        '×${order.items[i].quantity}',
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),

                          const SectionHeader(title: '做菜进度'),
                          AppCard(
                            child: Column(
                              children: [
                                for (var i = 0; i < order.steps.length; i++)
                                  _buildStepRow(order.steps[i], isLast: i == order.steps.length - 1),
                              ],
                            ),
                          ),

                          const SizedBox(height: 20),
                          if (_isChef && order.status == 'pending') ...[
                            if (order.ackedAt == null) ...[
                              GhostPillButton(
                                label: '先回一句「收到」',
                                onPressed: _busy
                                    ? null
                                    : () => _runAction(
                                          () => state.backend.ackOrder(order.id),
                                          '已告诉点菜人「收到」',
                                        ),
                              ),
                              const SizedBox(height: 10),
                            ],
                            PrimaryPillButton(
                              label: '接单，开始做',
                              loading: _busy,
                              onPressed: _accept,
                            ),
                            const SizedBox(height: 10),
                            GhostPillButton(
                              label: '这单做不了',
                              danger: true,
                              onPressed: _busy ? null : _reject,
                            ),
                            const SizedBox(height: 10),
                          ],
                          if (_isChef && order.status == 'accepted') ...[
                            PrimaryPillButton(
                              label: '已出餐，喊人开饭！',
                              loading: _busy,
                              onPressed: () => _runAction(
                                () => state.backend.finishOrder(order.id),
                                '已标记出餐！',
                              ),
                            ),
                            const SizedBox(height: 10),
                          ],
                          if (isMine && order.status == 'pending') ...[
                            GhostPillButton(
                              label: '撤销这一单',
                              danger: true,
                              onPressed: _busy
                                  ? null
                                  : () => _runAction(
                                        () => state.backend.cancelOrder(order.id),
                                        '已撤销点单',
                                      ),
                            ),
                            const SizedBox(height: 10),
                          ],
                          GhostPillButton(
                            label: '复制订单明细',
                            icon: CupertinoIcons.doc_on_doc,
                            onPressed: () {
                              final text = [
                                '【${order.kitchenName}】${order.dinerName} 的点单',
                                ...order.items.map((e) => '• ${e.dishName} ×${e.quantity}'),
                                if (order.note.isNotEmpty) '备注：${order.note}',
                              ].join('\n');
                              Clipboard.setData(ClipboardData(text: text));
                              showAppToast(context, '已复制订单明细');
                            },
                          ),
                          const SizedBox(height: 10),
                          GhostPillButton(
                            label: '再去这家点几道',
                            onPressed: () => pushCupertino(context, MenuScreen(kitchenId: order.kitchenId)),
                          ),
                        ],
                      ),
                    ),
    );
  }

  Widget _infoRow(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 74,
            child: Text(k, style: const TextStyle(fontSize: 13.5, color: AppColors.textSecondary)),
          ),
          Expanded(
            child: Text(v, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  Widget _buildStepRow(OrderStep step, {required bool isLast}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 12,
              height: 12,
              margin: const EdgeInsets.only(top: 4),
              decoration: BoxDecoration(
                color: step.done ? AppColors.primary : AppColors.border,
                shape: BoxShape.circle,
              ),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 28,
                color: step.done ? AppColors.primaryBorder : AppColors.border,
              ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    step.label,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: step.done ? FontWeight.w600 : FontWeight.w400,
                      color: step.done ? AppColors.textPrimary : AppColors.textMuted,
                    ),
                  ),
                ),
                if (step.done && step.at != null)
                  Text(
                    formatTimeHm(step.at!),
                    style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
