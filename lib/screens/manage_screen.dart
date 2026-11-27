import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/error_messages.dart';
import '../widgets/common_widgets.dart';
import 'dish_form_screen.dart';
import 'ingredients_screen.dart';
import 'kitchen_form_screen.dart';
import 'members_screen.dart';
import 'menu_screen.dart';

class ManageScreen extends StatefulWidget {
  final int kitchenId;

  const ManageScreen({super.key, required this.kitchenId});

  @override
  State<ManageScreen> createState() => _ManageScreenState();
}

class _ManageScreenState extends State<ManageScreen> {
  Kitchen? _kitchen;
  List<Category> _categories = [];
  List<Dish> _dishes = [];
  List<Ingredient> _ingredients = [];
  int _memberCount = 0;
  KitchenBadge _badge = const KitchenBadge();

  final _newCatCtrl = TextEditingController();
  bool _sortingCategories = false;
  bool _sortingDishes = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _newCatCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final backend = AppStateScope.read(context).backend;
      final kitchen = await backend.fetchKitchen(widget.kitchenId);
      final cats = await backend.fetchCategories(widget.kitchenId);
      final dishes = await backend.fetchDishes(widget.kitchenId);
      final ings = await backend.fetchIngredients(widget.kitchenId);
      final members = await backend.fetchMembers(widget.kitchenId);
      final badges = await backend.fetchKitchenBadges([widget.kitchenId]);

      if (!mounted) return;
      setState(() {
        _kitchen = kitchen;
        _categories = cats;
        _dishes = dishes;
        _ingredients = ings;
        _memberCount = members.length;
        _badge = badges[widget.kitchenId] ?? const KitchenBadge();
      });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addCategory() async {
    final name = _newCatCtrl.text.trim();
    if (name.isEmpty) return;
    try {
      await AppStateScope.read(context).backend.createCategory(widget.kitchenId, name);
      _newCatCtrl.clear();
      await _load();
      if (mounted) showAppToast(context, '已添加分类「$name」');
    } catch (e) {
      if (mounted) showAppToast(context, friendlyError(e), isError: true);
    }
  }

  Future<void> _toggleCategory(Category cat, bool value) async {
    try {
      await AppStateScope.read(context).backend.updateCategory(cat.id, isPublic: value);
      await _load();
    } catch (e) {
      if (mounted) showAppToast(context, friendlyError(e), isError: true);
    }
  }

  Future<void> _deleteCategory(Category cat) async {
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text('删除分类「${cat.name}」？'),
        content: const Text('该分类下的菜品不会被删除，会变为「未分类」。'),
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
      await AppStateScope.read(context).backend.deleteCategory(cat.id);
      await _load();
    } catch (e) {
      if (mounted) showAppToast(context, friendlyError(e), isError: true);
    }
  }

  Future<void> _saveCategoryOrder() async {
    final ids = _categories.map((c) => c.id).toList();
    try {
      await AppStateScope.read(context)
          .backend
          .reorderKitchenItems(widget.kitchenId, 'categories', ids, ids);
      if (mounted) {
        setState(() => _sortingCategories = false);
        showAppToast(context, '分类顺序已保存');
      }
    } catch (e) {
      if (mounted) showAppToast(context, friendlyError(e), isError: true);
    }
  }

  Future<void> _saveDishOrder() async {
    final ids = _dishes.map((d) => d.id).toList();
    try {
      await AppStateScope.read(context)
          .backend
          .reorderKitchenItems(widget.kitchenId, 'dishes', ids, ids);
      if (mounted) {
        setState(() => _sortingDishes = false);
        showAppToast(context, '菜品顺序已保存');
      }
    } catch (e) {
      if (mounted) showAppToast(context, friendlyError(e), isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final kitchen = _kitchen;
    final lowIngs = _ingredients.where((i) => i.isLow).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(kitchen?.name ?? '厨房管理'),
        actions: [
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            onPressed: () => pushCupertino(context, MenuScreen(kitchenId: widget.kitchenId)),
            child: const Text('预览菜单', style: TextStyle(fontWeight: FontWeight.w600)),
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

                  // Summary header card
                  AppCard(
                    color: AppColors.primaryLight,
                    border: Border.all(color: AppColors.primaryBorder),
                    child: Row(
                      children: [
                        KitchenAvatar(initial: kitchen?.initial ?? '厨', size: 48),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                kitchen?.name ?? '我的厨房',
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${_dishes.length} 道菜 · ${_ingredients.length} 种食材 · $_memberCount 位成员',
                                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SectionHeader(title: '厨房运营'),
                  AppCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        _navRow(
                          icon: CupertinoIcons.bell_fill,
                          iconColor: AppColors.waitText,
                          title: '待处理点单与缺料',
                          subtitle: _badge.pending > 0 || _badge.alerts > 0
                              ? '${_badge.pending} 单待接 · ${_badge.alerts} 条缺料提醒'
                              : '全部处理完了',
                          onTap: () {
                            AppStateScope.read(context).setTab(2);
                            Navigator.of(context).popUntil((r) => r.isFirst);
                          },
                        ),
                        const Divider(indent: 56),
                        _navRow(
                          icon: CupertinoIcons.cube_box_fill,
                          iconColor: AppColors.doingText,
                          title: '食材仓库',
                          subtitle: lowIngs.isNotEmpty
                              ? '${_ingredients.length} 种食材 · ${lowIngs.length} 种该补货'
                              : '${_ingredients.length} 种食材库存充足',
                          onTap: () async {
                            await pushCupertino(context, IngredientsScreen(kitchenId: widget.kitchenId));
                            _load();
                          },
                        ),
                        const Divider(indent: 56),
                        _navRow(
                          icon: CupertinoIcons.person_2_fill,
                          iconColor: AppColors.ackText,
                          title: '成员与邀请码',
                          subtitle: '共 $_memberCount 人 · 分享邀请码给好友',
                          onTap: () async {
                            final res = await pushCupertino(context, MembersScreen(kitchenId: widget.kitchenId));
                            if (res == 'left' && context.mounted) {
                              Navigator.of(context).pop();
                            } else {
                              _load();
                            }
                          },
                        ),
                        if (kitchen?.isOwner == true) ...[
                          const Divider(indent: 56),
                          _navRow(
                            icon: CupertinoIcons.slider_horizontal_3,
                            iconColor: AppColors.primary,
                            title: '厨房资料与公开设置',
                            subtitle: '${kitchen!.scopeText} · 修改名称或简介',
                            onTap: () async {
                              final res = await pushCupertino(
                                context,
                                KitchenFormScreen(existing: kitchen),
                              );
                              if (res == 'deleted' && context.mounted) {
                                Navigator.of(context).pop();
                              } else if (res != null) {
                                _load();
                              }
                            },
                          ),
                        ],
                      ],
                    ),
                  ),

                  SectionHeader(
                    title: '菜品分类（${_categories.length}）',
                    trailing: _categories.length > 1
                        ? CupertinoButton(
                            padding: EdgeInsets.zero,
                            onPressed: () {
                              if (_sortingCategories) {
                                _saveCategoryOrder();
                              } else {
                                setState(() => _sortingCategories = true);
                              }
                            },
                            child: Text(
                              _sortingCategories ? '完成排序' : '拖动排序',
                              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                            ),
                          )
                        : null,
                  ),
                  AppCard(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        if (_categories.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 14),
                            child: Text('还没有分类，先加一个「招牌菜」试试', style: TextStyle(color: AppColors.textMuted)),
                          )
                        else if (_sortingCategories)
                          ReorderableListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _categories.length,
                            onReorder: (oldIndex, newIndex) {
                              HapticFeedback.lightImpact();
                              setState(() {
                                if (newIndex > oldIndex) newIndex -= 1;
                                final item = _categories.removeAt(oldIndex);
                                _categories.insert(newIndex, item);
                              });
                            },
                            itemBuilder: (_, idx) {
                              final c = _categories[idx];
                              return ListTile(
                                key: ValueKey('cat-${c.id}'),
                                dense: true,
                                leading: const Icon(CupertinoIcons.line_horizontal_3, color: AppColors.textMuted),
                                title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                                trailing: Text('#${idx + 1}', style: const TextStyle(color: AppColors.textMuted)),
                              );
                            },
                          )
                        else
                          ..._categories.map(
                            (c) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(c.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                                  ),
                                  CupertinoSwitch(
                                    value: c.isPublic,
                                    activeTrackColor: AppColors.primary,
                                    onChanged: (v) => _toggleCategory(c, v),
                                  ),
                                  const SizedBox(width: 6),
                                  IconButton(
                                    icon: const Icon(CupertinoIcons.trash, size: 18, color: AppColors.danger),
                                    onPressed: () => _deleteCategory(c),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        const Divider(),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _newCatCtrl,
                                maxLength: 12,
                                decoration: const InputDecoration(
                                  hintText: '新分类名称，如「家常小炒」',
                                  counterText: '',
                                  isDense: true,
                                ),
                                onSubmitted: (_) => _addCategory(),
                              ),
                            ),
                            const SizedBox(width: 8),
                            CupertinoButton(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              color: AppColors.primary,
                              onPressed: _addCategory,
                              child: const Text('添加', style: TextStyle(color: Colors.white, fontSize: 14)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  SectionHeader(
                    title: '全部菜品（${_dishes.length}）',
                    trailing: _dishes.length > 1
                        ? CupertinoButton(
                            padding: EdgeInsets.zero,
                            onPressed: () {
                              if (_sortingDishes) {
                                _saveDishOrder();
                              } else {
                                setState(() => _sortingDishes = true);
                              }
                            },
                            child: Text(
                              _sortingDishes ? '完成排序' : '拖动排序',
                              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                            ),
                          )
                        : null,
                  ),
                  AppCard(
                    padding: EdgeInsets.zero,
                    child: _dishes.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(24),
                            child: Center(
                              child: Text('还没有菜品，点下方按钮新增第一道菜', style: TextStyle(color: AppColors.textMuted)),
                            ),
                          )
                        : _sortingDishes
                            ? ReorderableListView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _dishes.length,
                                onReorder: (oldIndex, newIndex) {
                                  HapticFeedback.lightImpact();
                                  setState(() {
                                    if (newIndex > oldIndex) newIndex -= 1;
                                    final item = _dishes.removeAt(oldIndex);
                                    _dishes.insert(newIndex, item);
                                  });
                                },
                                itemBuilder: (_, idx) {
                                  final d = _dishes[idx];
                                  return ListTile(
                                    key: ValueKey('dish-${d.id}'),
                                    leading: const Icon(CupertinoIcons.line_horizontal_3, color: AppColors.textMuted),
                                    title: Text(d.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                                    trailing: Text('#${idx + 1}', style: const TextStyle(color: AppColors.textMuted)),
                                  );
                                },
                              )
                            : Column(
                                children: [
                                  for (var i = 0; i < _dishes.length; i++) ...[
                                    if (i > 0) const Divider(indent: 16),
                                    ListTile(
                                      title: Text(_dishes[i].name, style: const TextStyle(fontWeight: FontWeight.w600)),
                                      subtitle: Wrap(
                                        spacing: 6,
                                        children: [
                                          Text(
                                            _dishes[i].isPublic ? '公开' : '仅成员',
                                            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                          ),
                                          if (!_dishes[i].isAvailable)
                                            const Text(
                                              '· 已下架',
                                              style: TextStyle(fontSize: 12, color: AppColors.danger),
                                            ),
                                        ],
                                      ),
                                      trailing: const Icon(CupertinoIcons.chevron_right, size: 16, color: AppColors.textMuted),
                                      onTap: () async {
                                        final res = await pushCupertino(
                                          context,
                                          DishFormScreen(kitchenId: widget.kitchenId, existing: _dishes[i]),
                                        );
                                        if (res != null) _load();
                                      },
                                    ),
                                  ],
                                ],
                              ),
                  ),

                  const SizedBox(height: 20),
                  PrimaryPillButton(
                    label: '＋ 新增菜品',
                    onPressed: () async {
                      final res = await pushCupertino(
                        context,
                        DishFormScreen(kitchenId: widget.kitchenId),
                      );
                      if (res != null) _load();
                    },
                  ),
                ],
              ),
            ),
    );
  }

  Widget _navRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: iconColor, size: 18),
      ),
      title: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
      trailing: const Icon(CupertinoIcons.chevron_right, size: 16, color: AppColors.textMuted),
      onTap: onTap,
    );
  }
}
