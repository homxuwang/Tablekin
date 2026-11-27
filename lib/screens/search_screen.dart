import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/error_messages.dart';
import '../widgets/common_widgets.dart';
import 'dish_detail_screen.dart';
import 'menu_screen.dart';

class SearchScreen extends StatefulWidget {
  final int? kitchenId;
  final String? kitchenName;

  const SearchScreen({super.key, this.kitchenId, this.kitchenName});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();
  Timer? _debounce;

  String _mode = 'dish'; // dish | kitchen
  String _scope = 'all'; // current | all
  String _tagMode = 'all'; // all | any
  final Set<String> _pickedTags = {};

  List<TagCount> _allTags = [];
  List<Dish> _dishes = [];
  List<Kitchen> _kitchens = [];
  bool _loading = false;
  bool _searched = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scope = widget.kitchenId != null ? 'current' : 'all';
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadTags());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _loadTags() async {
    try {
      final backend = AppStateScope.read(context).backend;
      final tags = await backend.listKitchenTags(
        kitchenId: _scope == 'current' ? (widget.kitchenId ?? 0) : 0,
      );
      if (mounted) setState(() => _allTags = tags);
    } catch (_) {}
  }

  void _onChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 280), _runSearch);
  }

  Future<void> _runSearch() async {
    final kw = _ctrl.text.trim();
    if (_mode == 'dish' && kw.isEmpty && _pickedTags.isEmpty) {
      setState(() {
        _searched = false;
        _dishes = [];
      });
      return;
    }
    if (_mode == 'kitchen' && kw.isEmpty) {
      setState(() {
        _searched = false;
        _kitchens = [];
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final backend = AppStateScope.read(context).backend;
      if (_mode == 'dish') {
        final rows = await backend.searchDishes(
          keyword: kw,
          kitchenId: _scope == 'current' ? widget.kitchenId : null,
          tags: _pickedTags.toList(),
          tagMode: _tagMode,
        );
        if (mounted) {
          setState(() {
            _dishes = rows;
            _searched = true;
          });
        }
      } else {
        final rows = await backend.searchKitchens(keyword: kw);
        if (mounted) {
          setState(() {
            _kitchens = rows;
            _searched = true;
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(right: 14),
          child: CupertinoSearchTextField(
            controller: _ctrl,
            autofocus: true,
            placeholder: _mode == 'dish' ? '搜菜名，如「红烧排骨」' : '搜厨房名，如「阿明」',
            onChanged: _onChanged,
            onSubmitted: (_) => _runSearch(),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 36),
        children: [
          CupertinoSlidingSegmentedControl<String>(
            groupValue: _mode,
            children: const {
              'dish': Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: Text('找菜')),
              'kitchen': Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: Text('找厨房')),
            },
            onValueChanged: (v) {
              if (v == null) return;
              setState(() {
                _mode = v;
                _searched = false;
              });
              _runSearch();
            },
          ),
          if (_mode == 'dish' && widget.kitchenId != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                _scopePill('本厨房${widget.kitchenName != null ? '「${widget.kitchenName}」' : ''}', 'current'),
                const SizedBox(width: 8),
                _scopePill('所有厨房', 'all'),
              ],
            ),
          ],
          if (_mode == 'dish' && _allTags.isNotEmpty) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                const Text('按标签筛选', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                const Spacer(),
                GestureDetector(
                  onTap: () {
                    setState(() => _tagMode = _tagMode == 'all' ? 'any' : 'all');
                    if (_pickedTags.isNotEmpty) _runSearch();
                  },
                  child: SmallTag(
                    label: _tagMode == 'all' ? '全部满足 ⇄' : '命中任一 ⇄',
                    bg: AppColors.surface,
                    fg: AppColors.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _allTags.map((t) {
                final picked = _pickedTags.contains(t.name);
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      if (picked) {
                        _pickedTags.remove(t.name);
                      } else {
                        _pickedTags.add(t.name);
                      }
                    });
                    _runSearch();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                    decoration: BoxDecoration(
                      color: picked ? AppColors.primary : AppColors.surface,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: picked ? AppColors.primary : AppColors.border),
                    ),
                    child: Text(
                      '${t.name} ${t.count}',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: picked ? Colors.white : AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 16),
          if (_error != null) InfoBanner(message: _error!),
          if (_loading)
            const Padding(padding: EdgeInsets.all(32), child: Center(child: CupertinoActivityIndicator()))
          else if (!_searched)
            EmptyStateView(
              icon: CupertinoIcons.search,
              title: _mode == 'dish' ? '输入菜名或点选标签找菜' : '输入好友厨房名搜索',
            )
          else if (_mode == 'dish') ...[
            if (_dishes.isEmpty)
              const EmptyStateView(icon: CupertinoIcons.search, title: '没有找到匹配的菜品')
            else
              ..._dishes.map(
                (d) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: AppCard(
                    padding: const EdgeInsets.all(12),
                    onTap: () => pushCupertino(context, DishDetailScreen(dishId: d.id)),
                    child: Row(
                      children: [
                        DishCover(initial: d.initial, size: 54, radius: 12),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(d.name, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600)),
                              if (d.description.isNotEmpty)
                                Text(
                                  d.description,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                                ),
                              if (d.tags.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Wrap(
                                  spacing: 4,
                                  children: d.tags.take(3).map((t) => SmallTag(label: t)).toList(),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const Icon(CupertinoIcons.chevron_right, size: 16, color: AppColors.textMuted),
                      ],
                    ),
                  ),
                ),
              ),
          ] else ...[
            if (_kitchens.isEmpty)
              const EmptyStateView(icon: CupertinoIcons.home, title: '没找到叫这个的厨房')
            else
              ..._kitchens.map(
                (k) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: AppCard(
                    padding: const EdgeInsets.all(14),
                    onTap: () => pushCupertino(context, MenuScreen(kitchenId: k.id)),
                    child: Row(
                      children: [
                        KitchenAvatar(initial: k.initial, size: 46),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(k.name, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 2),
                              Text(
                                k.description.isEmpty ? '点击查看菜单' : k.description,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        const Text('看菜单 ›', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _scopePill(String label, String value) {
    final on = _scope == value;
    return GestureDetector(
      onTap: () {
        setState(() => _scope = value);
        _loadTags();
        _runSearch();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: on ? AppColors.primaryLight : AppColors.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: on ? AppColors.primary : AppColors.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: on ? AppColors.primary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
