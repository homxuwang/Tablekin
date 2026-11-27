import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/availability.dart';
import '../utils/error_messages.dart';
import '../widgets/common_widgets.dart';
import 'cart_screen.dart';
import 'dish_detail_screen.dart';
import 'manage_screen.dart';
import 'search_screen.dart';

class MenuScreen extends StatefulWidget {
  final int kitchenId;

  const MenuScreen({super.key, required this.kitchenId});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  Kitchen? _kitchen;
  List<Category> _categories = [];
  List<Dish> _dishes = [];
  List<Ingredient> _ingredients = [];
  List<DishIngredient> _recipes = [];
  List<TagCount> _allTags = [];
  Map<String, String> _signedUrls = {};
  Map<int, DishAvailability> _availability = {};

  int _activeCategoryId = 0;
  final Set<String> _pickedTags = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppStateScope.read(context).setLastKitchenId(widget.kitchenId);
      _load();
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final backend = AppStateScope.read(context).backend;
      final kitchen = await backend.fetchKitchen(widget.kitchenId);
      final isMember = kitchen?.memberId != null;
      final cats = await backend.fetchCategories(widget.kitchenId, publicOnly: !isMember);
      final dishes = await backend.fetchDishes(widget.kitchenId, publicOnly: !isMember);
      final ings = await backend.fetchIngredients(widget.kitchenId);
      final recipes = await backend.fetchRecipes(kitchenId: widget.kitchenId);
      final tags = await backend.listKitchenTags(kitchenId: widget.kitchenId);

      final coverPaths = dishes.map((d) => d.coverImage).whereType<String>().toList();
      final signed = coverPaths.isNotEmpty ? await backend.signImageUrls(coverPaths) : <String, String>{};
      final avail = buildAvailability(dishes, ings, recipes);

      if (!mounted) return;
      setState(() {
        _kitchen = kitchen;
        _categories = cats;
        _dishes = dishes;
        _ingredients = ings;
        _recipes = recipes;
        _allTags = tags;
        _signedUrls = signed;
        _availability = avail;
      });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Dish> get _filteredDishes {
    return _dishes.where((d) {
      if (_activeCategoryId != 0 && d.categoryId != _activeCategoryId) return false;
      if (_pickedTags.isNotEmpty && !_pickedTags.every((t) => d.tags.contains(t))) {
        return false;
      }
      return true;
    }).toList();
  }

  Future<void> _explainShortage(Dish dish) async {
    final avail = _availability[dish.id];
    final lacks = avail?.lacks ?? const <DishShortageDetail>[];
    final state = AppStateScope.read(context);

    final text = lacks.isEmpty
        ? '这道菜暂时无法点单。'
        : lacks
            .map((l) => '• ${l.ingredientName}：需要 ${l.needed}${l.unit}，目前剩 ${l.stock}${l.unit}')
            .join('\n');

    final report = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text('「${dish.name}」食材不够'),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(text),
        ),
        actions: [
          CupertinoDialogAction(onPressed: () => Navigator.pop(ctx, false), child: const Text('知道了')),
          if (lacks.isNotEmpty)
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('提醒大厨补货'),
            ),
        ],
      ),
    );

    if (report == true && mounted) {
      try {
        await state.backend.reportShortage(
          kitchenId: widget.kitchenId,
          dinerName: state.dinerName.isNotEmpty ? state.dinerName : (state.currentUser?.displayName ?? '朋友'),
          problems: lacks,
        );
        if (mounted) showAppToast(context, '已提醒大厨补货');
      } catch (e) {
        if (mounted) showAppToast(context, friendlyError(e), isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.of(context);
    final isMember = _kitchen?.memberId != null;
    final cartCount = state.cartTotalCount(widget.kitchenId);
    final shown = _filteredDishes;
    final blockedCount = _dishes.where((d) => _availability[d.id]?.soldOut == true).length;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          children: [
            Text(_kitchen?.name ?? '今日菜单', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            if (_dishes.isNotEmpty)
              Text(
                '${_dishes.length} 道菜 · ${_categories.length} 个分类',
                style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary, fontWeight: FontWeight.w400),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(CupertinoIcons.search, size: 21),
            onPressed: () => pushCupertino(
              context,
              SearchScreen(kitchenId: widget.kitchenId, kitchenName: _kitchen?.name),
            ),
          ),
          if (isMember)
            IconButton(
              icon: const Icon(CupertinoIcons.slider_horizontal_3, size: 21),
              onPressed: () async {
                await pushCupertino(context, ManageScreen(kitchenId: widget.kitchenId));
                _load();
              },
            ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: InfoBanner(message: _error!),
                ),
              if (blockedCount > 0)
                Container(
                  width: double.infinity,
                  color: AppColors.waitBg,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    '有 $blockedCount 道菜因为食材不够暂时点不了（点击「缺料」可提醒大厨补货）',
                    style: const TextStyle(fontSize: 12.5, color: AppColors.waitText),
                  ),
                ),
              if (_allTags.isNotEmpty)
                Container(
                  height: 46,
                  color: AppColors.surface,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    children: [
                      _tagChip('全部', selected: _pickedTags.isEmpty, onTap: () => setState(() => _pickedTags.clear())),
                      ..._allTags.map((t) {
                        final picked = _pickedTags.contains(t.name);
                        return _tagChip(
                          '${t.name} ${t.count}',
                          selected: picked,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() {
                              if (picked) {
                                _pickedTags.remove(t.name);
                              } else {
                                _pickedTags.add(t.name);
                              }
                            });
                          },
                        );
                      }),
                    ],
                  ),
                ),
              const Divider(),
              Expanded(
                child: _loading
                    ? const Center(child: CupertinoActivityIndicator())
                    : Row(
                        children: [
                          // Left category rail
                          Container(
                            width: 92,
                            color: AppColors.surfaceSoft,
                            child: ListView(
                              padding: const EdgeInsets.only(bottom: 100),
                              children: [
                                _catRailItem(0, '全部'),
                                ..._categories.map((c) => _catRailItem(c.id, c.name)),
                              ],
                            ),
                          ),
                          // Right dish list
                          Expanded(
                            child: RefreshIndicator(
                              onRefresh: _load,
                              child: shown.isEmpty
                                  ? ListView(
                                      children: [
                                        EmptyStateView(
                                          icon: CupertinoIcons.square_list,
                                          title: _pickedTags.isNotEmpty ? '没有同时符合这些标签的菜' : '这个分类下还没有菜',
                                          subtitle: isMember ? '点右上角管理图标新增菜品吧' : '换个分类或标签看看',
                                        ),
                                      ],
                                    )
                                  : ListView.separated(
                                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 110),
                                      itemCount: shown.length,
                                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                                      itemBuilder: (_, idx) => _buildDishCard(shown[idx], isMember),
                                    ),
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),

          // Floating iOS frosted cart bar
          if (cartCount > 0)
            Positioned(
              left: 16,
              right: 16,
              bottom: MediaQuery.of(context).padding.bottom + 14,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(18, 10, 10, 10),
                    decoration: BoxDecoration(
                      color: const Color(0xE81E2329),
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.18),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '$cartCount',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            '份菜已选好',
                            style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
                          ),
                        ),
                        GestureDetector(
                          onTap: () async {
                            HapticFeedback.mediumImpact();
                            await pushCupertino(
                              context,
                              CartScreen(
                                kitchenId: widget.kitchenId,
                                kitchenName: _kitchen?.name ?? '点菜清单',
                                dishes: _dishes,
                                ingredients: _ingredients,
                                recipes: _recipes,
                              ),
                            );
                            _load();
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Text(
                              '去下单 ›',
                              style: TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _tagChip(String label, {required bool selected, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.surfaceSoft,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? AppColors.primary : AppColors.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _catRailItem(int id, String name) {
    final active = _activeCategoryId == id;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _activeCategoryId = id);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 15),
        decoration: BoxDecoration(
          color: active ? AppColors.surface : Colors.transparent,
          border: Border(
            left: BorderSide(
              color: active ? AppColors.primary : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Text(
          name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            color: active ? AppColors.primary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildDishCard(Dish dish, bool isMember) {
    final state = AppStateScope.of(context);
    final avail = _availability[dish.id];
    final soldOut = !dish.isAvailable || (avail?.soldOut == true);
    final count = state.dishCartCount(widget.kitchenId, dish.id);
    final imageUrl = dish.coverImage != null ? _signedUrls[dish.coverImage!] : null;

    return AppCard(
      padding: const EdgeInsets.all(11),
      onTap: () async {
        final res = await pushCupertino(
          context,
          DishDetailScreen(dishId: dish.id, canEdit: isMember),
        );
        if (res != null) _load();
      },
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Opacity(
            opacity: soldOut ? 0.55 : 1,
            child: DishCover(imageUrl: imageUrl, initial: dish.initial, size: 74, radius: 14),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dish.name,
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: soldOut ? AppColors.textMuted : AppColors.textPrimary,
                  ),
                ),
                if (dish.description.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    dish.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.35),
                  ),
                ],
                if (dish.tags.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 5,
                    runSpacing: 4,
                    children: dish.tags.take(3).map((t) => SmallTag(label: t)).toList(),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 5,
                        runSpacing: 4,
                        children: [
                          if (avail != null && avail.text.isNotEmpty)
                            SmallTag(
                              label: avail.text,
                              bg: avail.soldOut ? AppColors.dangerBg : AppColors.doingBg,
                              fg: avail.soldOut ? AppColors.danger : AppColors.doingText,
                            ),
                          if (!dish.isAvailable)
                            const SmallTag(label: '已下架', bg: AppColors.mutedBg, fg: AppColors.textMuted),
                        ],
                      ),
                    ),
                    InlineCartStepper(
                      count: count,
                      soldOut: soldOut,
                      onAdd: () => state.addToCart(widget.kitchenId, dish),
                      onRemove: () => state.decreaseFromCart(widget.kitchenId, dish.id),
                      onSoldOutTap: () => _explainShortage(dish),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
