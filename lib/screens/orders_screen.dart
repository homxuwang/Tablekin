import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/error_messages.dart';
import '../utils/meal_time.dart';
import '../widgets/common_widgets.dart';
import 'order_detail_screen.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  String _segment = 'received'; // mine | received
  int _filterKitchenId = 0;

  List<Kitchen> _myKitchens = [];
  List<KitchenOrder> _myOrders = [];
  List<KitchenOrder> _receivedOrders = [];
  List<AppNotification> _notices = [];
  List<ShortageAlert> _alerts = [];

  bool _loading = true;
  int? _busyOrderId;
  String? _error;
  int _lastDataVersion = -1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = AppStateScope.of(context);
    if (_lastDataVersion != state.dataVersion) {
      _lastDataVersion = state.dataVersion;
      _load();
    }
  }

  Future<void> _load() async {
    final state = AppStateScope.read(context);
    if (!state.isSignedIn) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final backend = state.backend;
      final kitchens = await backend.fetchMyKitchens();
      final myOrders = await backend.fetchMyOrders();
      final received = await backend.fetchReceivedOrders(kitchens.map((k) => k.id).toList());
      final notices = await backend.fetchUnreadNotifications();
      final alerts = kitchens.isNotEmpty ? await backend.fetchShortageAlerts() : <ShortageAlert>[];

      if (!mounted) return;
      setState(() {
        _myKitchens = kitchens;
        _myOrders = myOrders;
        _receivedOrders = received;
        _notices = notices;
        _alerts = alerts;
        if (kitchens.isEmpty && _segment == 'received') {
          _segment = 'mine';
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _runOrderAction(int orderId, Future<void> Function() action, String msg) async {
    final state = AppStateScope.read(context);
    setState(() => _busyOrderId = orderId);
    try {
      await action();
      await state.refreshBadges();
      await _load();
      if (mounted) showAppToast(context, msg);
    } catch (e) {
      if (mounted) showAppToast(context, friendlyError(e), isError: true);
    } finally {
      if (mounted) setState(() => _busyOrderId = null);
    }
  }

  Future<void> _acceptOrder(KitchenOrder order) async {
    setState(() => _busyOrderId = order.id);
    try {
      final res = await AppStateScope.read(context).backend.acceptOrder(order.id);
      if (!mounted) return;
      if (!res.ok) {
        final detail = res.problems
            .map((p) => '${p.ingredientName}：需 ${p.needed}，剩 ${p.stock}')
            .join('\n');
        showCupertinoDialog<void>(
          context: context,
          builder: (ctx) => CupertinoAlertDialog(
            title: const Text('食材不够，暂时无法接单'),
            content: Text(detail),
            actions: [
              CupertinoDialogAction(onPressed: () => Navigator.pop(ctx), child: const Text('知道了')),
            ],
          ),
        );
      } else {
        await AppStateScope.read(context).refreshBadges();
        await _load();
        if (mounted) showAppToast(context, '已接单，库存已扣减');
      }
    } catch (e) {
      if (mounted) showAppToast(context, friendlyError(e), isError: true);
    } finally {
      if (mounted) setState(() => _busyOrderId = null);
    }
  }

  Future<void> _rejectOrder(KitchenOrder order) async {
    final ctrl = TextEditingController();
    final reason = await showCupertinoDialog<String>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('这单做不了'),
        content: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: CupertinoTextField(controller: ctrl, placeholder: '回复原因（选填）'),
        ),
        actions: [
          CupertinoDialogAction(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    if (reason == null || !mounted) return;
    await _runOrderAction(
      order.id,
      () => AppStateScope.read(context).backend.rejectOrder(order.id, reason: reason),
      '已回复点菜人',
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.of(context);
    final pendingReceived = _receivedOrders.where((o) => o.status == 'pending').length;

    final shownOrders = _segment == 'mine'
        ? _myOrders
        : _receivedOrders
            .where((o) => _filterKitchenId == 0 || o.kitchenId == _filterKitchenId)
            .toList();

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '订单',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.5),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: CupertinoSlidingSegmentedControl<String>(
                      groupValue: _segment,
                      children: {
                        'mine': const Padding(
                          padding: EdgeInsets.symmetric(vertical: 6),
                          child: Text('我点的', style: TextStyle(fontWeight: FontWeight.w600)),
                        ),
                        'received': Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Text(
                            pendingReceived > 0 ? '我收到的（$pendingReceived）' : '我收到的',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      },
                      onValueChanged: (v) {
                        if (v != null) setState(() => _segment = v);
                      },
                    ),
                  ),
                ],
              ),
            ),

            if (_segment == 'received' && _myKitchens.length > 1)
              SizedBox(
                height: 38,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    _filterChip('全部厨房', 0),
                    ..._myKitchens.map((k) => _filterChip(k.name, k.id)),
                  ],
                ),
              ),

            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  await _load();
                  await state.refreshBadges();
                },
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 36),
                  children: [
                    if (_error != null) InfoBanner(message: _error!),

                    // Unread notifications strip
                    if (_notices.isNotEmpty) ...[
                      AppCard(
                        color: AppColors.ackBg,
                        border: Border.all(color: AppColors.ackText.withValues(alpha: 0.25)),
                        padding: const EdgeInsets.all(13),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  '新消息提醒（${_notices.length}）',
                                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.ackText),
                                ),
                                const Spacer(),
                                GestureDetector(
                                  onTap: () async {
                                    await state.backend.markNotificationsRead();
                                    await state.refreshBadges();
                                    await _load();
                                  },
                                  child: const Text('全部已读', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.ackText)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            ..._notices.take(3).map(
                              (n) => GestureDetector(
                                onTap: () async {
                                  await state.backend.markNotificationsRead(ids: [n.id]);
                                  await state.refreshBadges();
                                  if (n.orderId != null && context.mounted) {
                                    await pushCupertino(context, OrderDetailScreen(orderId: n.orderId!));
                                  }
                                  _load();
                                },
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(n.title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                                      if (n.body.isNotEmpty)
                                        Text(n.body, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // Shortage alerts for chef
                    if (_segment == 'received' && _alerts.isNotEmpty) ...[
                      AppCard(
                        color: AppColors.dangerBg,
                        border: Border.all(color: AppColors.dangerBorder),
                        padding: const EdgeInsets.all(13),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  '缺料提醒（${_alerts.length}）',
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.danger),
                                ),
                                const Spacer(),
                                GestureDetector(
                                  onTap: () async {
                                    await state.backend.markShortageAlertsRead(_alerts.map((a) => a.id).toList());
                                    await _load();
                                  },
                                  child: const Text('知道了', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.danger)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            ..._alerts.map(
                              (a) => Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  '${a.dinerName} 想点「${a.dishName}」，缺 ${a.ingredientName}（需 ${a.needed}，剩 ${a.stock}）',
                                  style: const TextStyle(fontSize: 13, color: AppColors.danger),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.all(36),
                        child: Center(child: CupertinoActivityIndicator()),
                      )
                    else if (shownOrders.isEmpty)
                      EmptyStateView(
                        icon: CupertinoIcons.doc_text,
                        title: _segment == 'received' ? '还没有收到点单' : '你还没有点过菜',
                        subtitle: _segment == 'received' ? '把厨房菜单分享给朋友，他们随时能来点单' : '去「点菜」页挑一家厨房试试吧',
                        action: _segment == 'mine'
                            ? GhostPillButton(label: '去看看谁家开饭', onPressed: () => state.setTab(0))
                            : null,
                      )
                    else
                      ...shownOrders.map(_buildOrderCard),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(String label, int id) {
    final on = _filterKitchenId == id;
    return GestureDetector(
      onTap: () => setState(() => _filterKitchenId = id),
      child: Container(
        margin: const EdgeInsets.only(right: 8, bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: on ? AppColors.primary : AppColors.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: on ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildOrderCard(KitchenOrder order) {
    final state = AppStateScope.read(context);
    final busy = _busyOrderId == order.id;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        padding: const EdgeInsets.all(15),
        onTap: () async {
          await pushCupertino(context, OrderDetailScreen(orderId: order.id));
          _load();
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _segment == 'received'
                        ? '${order.dinerName} 点的'
                        : (order.kitchenName.isEmpty ? '厨房' : order.kitchenName),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
                StatusPill(status: order.statusInfo),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '想吃：${mealScheduleText(orderDate: order.orderDate, mealTimeType: order.mealTimeType, start: order.mealTimeStart, end: order.mealTimeEnd)} · ${order.items.length} 道菜 共 ${order.totalPortions} 份',
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.surfaceSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: order.items
                    .map(
                      (item) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(item.dishName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                            ),
                            Text('×${item.quantity}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.primary)),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
            if (order.note.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('备注：${order.note}', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            ],
            if (order.rejectReason.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('回复：${order.rejectReason}', style: const TextStyle(fontSize: 13, color: AppColors.danger)),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  '${formatMonthDay(order.createdAt)} ${formatTimeHm(order.createdAt)}',
                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
                const Spacer(),
                if (_segment == 'received' && order.status == 'pending') ...[
                  if (order.ackedAt == null) ...[
                    _orderBtn(
                      '收到',
                      busy: busy,
                      onTap: () => _runOrderAction(order.id, () => state.backend.ackOrder(order.id), '已回执「收到」'),
                    ),
                    const SizedBox(width: 8),
                  ],
                  _orderBtn(
                    '接单',
                    primary: true,
                    busy: busy,
                    onTap: () => _acceptOrder(order),
                  ),
                  const SizedBox(width: 8),
                  _orderBtn('做不了', danger: true, busy: busy, onTap: () => _rejectOrder(order)),
                ],
                if (_segment == 'received' && order.status == 'accepted')
                  _orderBtn(
                    '已出餐',
                    primary: true,
                    busy: busy,
                    onTap: () => _runOrderAction(order.id, () => state.backend.finishOrder(order.id), '已标记出餐！'),
                  ),
                if (_segment == 'mine' && order.status == 'pending')
                  _orderBtn(
                    '撤销',
                    danger: true,
                    busy: busy,
                    onTap: () => _runOrderAction(order.id, () => state.backend.cancelOrder(order.id), '已撤销点单'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _orderBtn(
    String label, {
    bool primary = false,
    bool danger = false,
    bool busy = false,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: busy ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: primary
              ? AppColors.primary
              : danger
                  ? AppColors.dangerBg
                  : AppColors.surfaceSoft,
          borderRadius: BorderRadius.circular(999),
          border: primary
              ? null
              : Border.all(color: danger ? AppColors.dangerBorder : AppColors.border),
        ),
        child: Text(
          busy ? '…' : label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: primary
                ? Colors.white
                : danger
                    ? AppColors.danger
                    : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}
