import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/error_messages.dart';
import '../widgets/common_widgets.dart';
import 'dish_form_screen.dart';
import 'menu_screen.dart';

class DishDetailScreen extends StatefulWidget {
  final int dishId;
  final bool canEdit;

  const DishDetailScreen({
    super.key,
    required this.dishId,
    this.canEdit = false,
  });

  @override
  State<DishDetailScreen> createState() => _DishDetailScreenState();
}

class _DishDetailScreenState extends State<DishDetailScreen> {
  Dish? _dish;
  Map<String, String> _signedUrls = {};
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
      final backend = AppStateScope.read(context).backend;
      final dish = await backend.fetchDish(widget.dishId);
      Map<String, String> urls = {};
      if (dish != null && dish.allImages.isNotEmpty) {
        urls = await backend.signImageUrls(dish.allImages);
      }
      if (!mounted) return;
      setState(() {
        _dish = dish;
        _signedUrls = urls;
      });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dish = _dish;
    final recipeVisible = widget.canEdit || (dish?.isRecipePublic == true);

    return Scaffold(
      appBar: AppBar(
        title: Text(dish?.name ?? '菜品详情'),
        actions: [
          if (widget.canEdit && dish != null)
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              onPressed: () async {
                final res = await pushCupertino(
                  context,
                  DishFormScreen(kitchenId: dish.kitchenId, existing: dish),
                );
                if (!context.mounted) return;
                if (res == 'deleted') {
                  Navigator.of(context).pop('deleted');
                } else if (res != null) {
                  _load();
                }
              },
              child: const Text('编辑', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CupertinoActivityIndicator())
          : _error != null
              ? Center(child: InfoBanner(message: _error!))
              : dish == null
                  ? const EmptyStateView(icon: CupertinoIcons.exclamationmark_circle, title: '找不到这道菜')
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                      children: [
                        // Hero image or warm culinary banner
                        ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: SizedBox(
                            height: 220,
                            child: dish.allImages.isNotEmpty
                                ? PageView.builder(
                                    itemCount: dish.allImages.length,
                                    itemBuilder: (_, idx) {
                                      final url = _signedUrls[dish.allImages[idx]];
                                      if (url != null && url.startsWith('http')) {
                                        return Image.network(url, fit: BoxFit.cover);
                                      }
                                      return _heroFallback(dish.name);
                                    },
                                  )
                                : _heroFallback(dish.name),
                          ),
                        ),
                        const SizedBox(height: 14),
                        AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                dish.name,
                                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                              ),
                              if (dish.description.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  dish.description,
                                  style: const TextStyle(
                                    fontSize: 14.5,
                                    color: AppColors.textSecondary,
                                    height: 1.5,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  SmallTag(
                                    label: dish.isPublic ? '菜单公开' : '仅成员可见',
                                    bg: AppColors.mutedBg,
                                    fg: AppColors.textSecondary,
                                  ),
                                  SmallTag(
                                    label: dish.isAvailable ? '今日可点' : '已下架',
                                    bg: dish.isAvailable ? AppColors.doingBg : AppColors.dangerBg,
                                    fg: dish.isAvailable ? AppColors.doingText : AppColors.danger,
                                  ),
                                  SmallTag(
                                    label: dish.isRecipePublic ? '菜谱公开' : '菜谱私密',
                                    bg: AppColors.mutedBg,
                                    fg: AppColors.textSecondary,
                                  ),
                                ],
                              ),
                              if (dish.tags.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  children: dish.tags.map((t) => SmallTag(label: '# $t')).toList(),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SectionHeader(title: '做法与菜谱'),
                        AppCard(
                          child: dish.recipe.isNotEmpty && recipeVisible
                              ? Text(
                                  dish.recipe,
                                  style: const TextStyle(fontSize: 15, height: 1.7, color: AppColors.textPrimary),
                                )
                              : Text(
                                  dish.recipe.isNotEmpty ? '这道菜的菜谱暂未公开' : '大厨还没有写菜谱步骤',
                                  style: const TextStyle(fontSize: 14, color: AppColors.textMuted),
                                ),
                        ),
                        const SizedBox(height: 20),
                        if (widget.canEdit)
                          PrimaryPillButton(
                            label: '编辑这道菜',
                            onPressed: () async {
                              final res = await pushCupertino(
                                context,
                                DishFormScreen(kitchenId: dish.kitchenId, existing: dish),
                              );
                              if (!context.mounted) return;
                              if (res == 'deleted') {
                                Navigator.of(context).pop('deleted');
                              } else if (res != null) {
                                _load();
                              }
                            },
                          )
                        else
                          GhostPillButton(
                            label: '去这个厨房点菜',
                            onPressed: () => pushCupertino(context, MenuScreen(kitchenId: dish.kitchenId)),
                          ),
                      ],
                    ),
    );
  }

  Widget _heroFallback(String name) {
    return Container(
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFF1E2), Color(0xFFFAD7B6)],
        ),
      ),
      child: Text(
        name,
        style: const TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w700,
          color: AppColors.primary,
        ),
      ),
    );
  }
}
