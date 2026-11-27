import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/error_messages.dart';
import '../utils/meal_time.dart';
import '../widgets/common_widgets.dart';
import 'join_kitchen_screen.dart';
import 'menu_screen.dart';
import 'order_detail_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Kitchen> _publicKitchens = [];
  Map<int, int> _dishCounts = {};
  List<KitchenOrder> _ongoingOrders = [];
  Kitchen? _lastKitchen;
  int _mineCount = 0;

  bool _loading = true;
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
      final myKitchens = await backend.fetchMyKitchens();
      final myIds = myKitchens.map((k) => k.id).toSet();
      final allPublic = await backend.searchKitchens();
      final others = allPublic.where((k) => !myIds.contains(k.id)).toList();
      final displayList = others.isNotEmpty ? others : allPublic;
      final counts = await backend.countPublicDishes(displayList.map((k) => k.id).toList());
      final myOrders = await backend.fetchMyOrders();
      final ongoing = myOrders.where((o) => o.isOngoing).toList();

      Kitchen? last;
      if (state.lastKitchenId != null) {
        last = await backend.fetchKitchen(state.lastKitchenId!);
      }

      if (!mounted) return;
      setState(() {
        _mineCount = myKitchens.length;
        _publicKitchens = displayList;
        _dishCounts = counts;
        _ongoingOrders = ongoing;
        _lastKitchen = last;
      });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.of(context);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async {
            await _load();
            await state.refreshBadges();
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 36),
            children: [
              // Warm iOS hero header
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '今天想吃点什么',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _mineCount > 0 ? '挑一家朋友厨房点菜，或去「下厨」管自己的菜单' : '挑一家厨房，点几道菜让 TA 做',
                          style: const TextStyle(fontSize: 13.5, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => pushCupertino(context, const SettingsScreen()),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: state.isCloud ? AppColors.doingBg : AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: state.isCloud ? AppColors.doingText.withValues(alpha: 0.3) : AppColors.primaryBorder,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            state.isCloud ? CupertinoIcons.cloud_fill : CupertinoIcons.sparkles,
                            size: 14,
                            color: state.isCloud ? AppColors.doingText : AppColors.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            state.isCloud ? '云端' : '体验版',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: state.isCloud ? AppColors.doingText : AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              // Quick search bar + join code button
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => pushCupertino(context, const SearchScreen()),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: const Row(
                          children: [
                            Icon(CupertinoIcons.search, size: 17, color: AppColors.textMuted),
                            SizedBox(width: 8),
                            Text(
                              '搜菜名、标签或朋友的厨房…',
                              style: TextStyle(fontSize: 14.5, color: AppColors.textMuted),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => pushCupertino(context, const JoinKitchenScreen()),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.primaryBorder),
                      ),
                      child: const Row(
                        children: [
                          Icon(CupertinoIcons.ticket, size: 17, color: AppColors.primary),
                          SizedBox(width: 4),
                          Text(
                            '输码',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              if (_error != null) ...[
                const SizedBox(height: 12),
                InfoBanner(message: _error!),
              ],

              // Resume last kitchen
              if (_lastKitchen != null) ...[
                const SizedBox(height: 14),
                AppCard(
                  color: AppColors.primaryLight,
                  border: Border.all(color: AppColors.primaryBorder),
                  padding: const EdgeInsets.all(13),
                  onTap: () => pushCupertino(context, MenuScreen(kitchenId: _lastKitchen!.id)),
                  child: Row(
                    children: [
                      KitchenAvatar(initial: _lastKitchen!.initial, size: 40),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('上次点菜的地方', style: TextStyle(fontSize: 11.5, color: AppColors.primary)),
                            Text(
                              _lastKitchen!.name,
                              style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                      const Text(
                        '继续点菜 ›',
                        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.primary),
                      ),
                    ],
                  ),
                ),
              ],

              // Ongoing orders
              if (_ongoingOrders.isNotEmpty) ...[
                const SectionHeader(title: '进行中的点单'),
                ..._ongoingOrders.map(
                  (o) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: AppCard(
                      padding: const EdgeInsets.all(14),
                      onTap: () => pushCupertino(context, OrderDetailScreen(orderId: o.id)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  o.kitchenName.isEmpty ? '厨房' : o.kitchenName,
                                  style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
                                ),
                              ),
                              StatusPill(status: o.statusInfo),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${o.dishesSummary} · 共 ${o.totalPortions} 份',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '想吃：${mealScheduleText(orderDate: o.orderDate, mealTimeType: o.mealTimeType, start: o.mealTimeStart, end: o.mealTimeEnd)} · ${formatTimeHm(o.createdAt)} 下单',
                            style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],

              const SectionHeader(title: '今天开饭的厨房'),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(36),
                  child: Center(child: CupertinoActivityIndicator()),
                )
              else if (_publicKitchens.isEmpty)
                EmptyStateView(
                  icon: CupertinoIcons.flame,
                  title: '还没有公开的厨房',
                  subtitle: '可以自己开一个厨房，或者输入朋友的邀请码加入。',
                  action: PrimaryPillButton(
                    label: '去「下厨」开一个厨房',
                    onPressed: () => state.setTab(1),
                  ),
                )
              else
                ..._publicKitchens.map((k) {
                  final count = _dishCounts[k.id] ?? 0;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: AppCard(
                      padding: const EdgeInsets.all(14),
                      onTap: () => pushCupertino(context, MenuScreen(kitchenId: k.id)),
                      child: Row(
                        children: [
                          KitchenAvatar(initial: k.initial, size: 50),
                          const SizedBox(width: 13),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  k.name,
                                  style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  k.description.isEmpty ? '这个厨房还没有写简介' : k.description,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.35),
                                ),
                                const SizedBox(height: 8),
                                SmallTag(
                                  label: count > 0 ? '$count 道在售菜品' : '暂无在售菜品',
                                  bg: count > 0 ? AppColors.primaryLight : AppColors.mutedBg,
                                  fg: count > 0 ? AppColors.primary : AppColors.textMuted,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(
                              color: AppColors.primaryLight,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              count > 0 ? '去点菜' : '看看',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
            ],
          ),
        ),
      ),
    );
  }
}
