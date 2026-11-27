import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/error_messages.dart';
import '../widgets/common_widgets.dart';
import 'join_kitchen_screen.dart';
import 'kitchen_form_screen.dart';
import 'manage_screen.dart';
import 'members_screen.dart';
import 'menu_screen.dart';

class ChefScreen extends StatefulWidget {
  const ChefScreen({super.key});

  @override
  State<ChefScreen> createState() => _ChefScreenState();
}

class _ChefScreenState extends State<ChefScreen> {
  List<Kitchen> _kitchens = [];
  Map<int, int> _dishCounts = {};
  Map<int, KitchenBadge> _badges = {};
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
      final kitchens = await backend.fetchMyKitchens();
      final ids = kitchens.map((k) => k.id).toList();
      final counts = await backend.countPublicDishes(ids);
      final badges = await backend.fetchKitchenBadges(ids);
      if (!mounted) return;
      setState(() {
        _kitchens = kitchens;
        _dishCounts = counts;
        _badges = badges;
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
    final todoKitchens = _kitchens.where((k) {
      final b = _badges[k.id];
      return b != null && (b.pending > 0 || b.alerts > 0);
    }).toList();

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
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '下厨',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          '菜单、食材库存与好友协作都在这儿管',
                          style: TextStyle(fontSize: 13.5, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(999),
                    onPressed: () async {
                      final created = await pushCupertino(context, const KitchenFormScreen());
                      if (created != null) _load();
                    },
                    child: const Text('＋ 新建', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),

              if (_error != null) ...[
                const SizedBox(height: 12),
                InfoBanner(message: _error!),
              ],

              if (todoKitchens.isNotEmpty) ...[
                const SizedBox(height: 14),
                AppCard(
                  color: AppColors.waitBg,
                  border: Border.all(color: AppColors.primaryBorder),
                  onTap: () => state.setTab(2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(CupertinoIcons.bell_fill, size: 16, color: AppColors.waitText),
                          SizedBox(width: 6),
                          Text(
                            '待你处理',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.waitText),
                          ),
                          Spacer(),
                          Text('去订单页回话 ›', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primary)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ...todoKitchens.map((k) {
                        final b = _badges[k.id]!;
                        final parts = <String>[];
                        if (b.pending > 0) parts.add('${b.pending} 单待接');
                        if (b.alerts > 0) parts.add('${b.alerts} 条缺料提醒');
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            children: [
                              Text(k.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                              const Spacer(),
                              Text(parts.join(' · '), style: const TextStyle(fontSize: 13, color: AppColors.waitText)),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ],

              const SectionHeader(title: '我的厨房'),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(36),
                  child: Center(child: CupertinoActivityIndicator()),
                )
              else if (_kitchens.isEmpty)
                EmptyStateView(
                  icon: CupertinoIcons.house,
                  title: '你还没有自己的厨房',
                  subtitle: '起个名字、写几道拿手菜，就能让家人朋友来点单了。',
                )
              else
                ..._kitchens.map((k) {
                  final count = _dishCounts[k.id] ?? 0;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: AppCard(
                      padding: const EdgeInsets.all(15),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              KitchenAvatar(initial: k.initial, size: 46),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            k.name,
                                            style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        SmallTag(label: k.roleText),
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      '$count 道在售菜 · ${k.scopeText}',
                                      style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: _toolBtn(
                                  '菜单',
                                  primary: true,
                                  onTap: () => pushCupertino(context, MenuScreen(kitchenId: k.id)),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _toolBtn(
                                  '管理',
                                  onTap: () async {
                                    await pushCupertino(context, ManageScreen(kitchenId: k.id));
                                    _load();
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _toolBtn(
                                  '成员',
                                  onTap: () async {
                                    await pushCupertino(context, MembersScreen(kitchenId: k.id));
                                    _load();
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _toolBtn(
                                  '分享',
                                  onTap: () {
                                    SharePlus.instance.share(
                                      ShareParams(
                                        text: '来「一桌人」看看我的厨房【${k.name}】，点几道想吃的菜吧！',
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }),

              const SizedBox(height: 8),
              PrimaryPillButton(
                label: '＋ 新建厨房',
                onPressed: () async {
                  final created = await pushCupertino(context, const KitchenFormScreen());
                  if (created != null) _load();
                },
              ),
              const SizedBox(height: 10),
              GhostPillButton(
                label: '用邀请码加入朋友的厨房',
                icon: CupertinoIcons.ticket,
                onPressed: () async {
                  await pushCupertino(context, const JoinKitchenScreen());
                  _load();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _toolBtn(String label, {bool primary = false, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: primary ? AppColors.primaryLight : AppColors.surfaceSoft,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: primary ? AppColors.primaryBorder : AppColors.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: primary ? AppColors.primary : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}
