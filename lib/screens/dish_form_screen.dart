import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/error_messages.dart';
import '../widgets/common_widgets.dart';

class DishFormScreen extends StatefulWidget {
  final int kitchenId;
  final Dish? existing;

  const DishFormScreen({super.key, required this.kitchenId, this.existing});

  @override
  State<DishFormScreen> createState() => _DishFormScreenState();
}

class _DishFormScreenState extends State<DishFormScreen> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _recipeCtrl;
  final _tagInputCtrl = TextEditingController();

  List<Category> _categories = [];
  List<Ingredient> _ingredients = [];
  List<TagCount> _tagSuggestions = [];

  int? _categoryId;
  List<String> _tags = [];
  List<String> _imagePaths = [];
  Map<String, String> _signedUrls = {};
  final List<_RecipeRow> _recipeRows = [];

  bool _isPublic = true;
  bool _isRecipePublic = true;
  bool _isAvailable = true;

  bool _loading = true;
  bool _saving = false;
  bool _uploading = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final d = widget.existing;
    _nameCtrl = TextEditingController(text: d?.name ?? '');
    _descCtrl = TextEditingController(text: d?.description ?? '');
    _recipeCtrl = TextEditingController(text: d?.recipe ?? '');
    _categoryId = d?.categoryId;
    _tags = List<String>.from(d?.tags ?? const []);
    _imagePaths = List<String>.from(d?.allImages ?? const []);
    _isPublic = d?.isPublic ?? true;
    _isRecipePublic = d?.isRecipePublic ?? true;
    _isAvailable = d?.isAvailable ?? true;

    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMeta());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _recipeCtrl.dispose();
    _tagInputCtrl.dispose();
    for (final r in _recipeRows) {
      r.amountCtrl.dispose();
    }
    super.dispose();
  }

  Future<void> _loadMeta() async {
    try {
      final backend = AppStateScope.read(context).backend;
      final cats = await backend.fetchCategories(widget.kitchenId);
      final ings = await backend.fetchIngredients(widget.kitchenId);
      final tags = await backend.listKitchenTags(kitchenId: widget.kitchenId);
      Map<String, String> urls = {};
      if (_imagePaths.isNotEmpty) {
        urls = await backend.signImageUrls(_imagePaths);
      }
      if (widget.existing != null) {
        final rows = await backend.fetchRecipes(dishId: widget.existing!.id);
        for (final r in rows) {
          final ing = ings.where((i) => i.id == r.ingredientId).firstOrNull;
          if (ing != null) {
            _recipeRows.add(_RecipeRow(
              ingredient: ing,
              amountCtrl: TextEditingController(
                text: r.amount == r.amount.roundToDouble()
                    ? r.amount.toInt().toString()
                    : r.amount.toString(),
              ),
            ));
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _categories = cats;
        _ingredients = ings;
        _tagSuggestions = tags;
        _signedUrls = urls;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = friendlyError(e);
          _loading = false;
        });
      }
    }
  }

  void _addTag(String raw) {
    final cleaned = raw.trim().replaceAll(RegExp(r'[,，"\x27]'), '');
    if (cleaned.isEmpty || _tags.contains(cleaned) || _tags.length >= 12) return;
    setState(() {
      _tags.add(cleaned);
      _tagInputCtrl.clear();
    });
  }

  Future<void> _pickImage() async {
    if (_imagePaths.length >= 9 || _uploading) return;
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1440, imageQuality: 85);
    if (picked == null || !mounted) return;
    setState(() => _uploading = true);
    try {
      final bytes = await picked.readAsBytes();
      final backend = AppStateScope.read(context).backend;
      final path = await backend.uploadDishImage(bytes, picked.name);
      final signed = await backend.signImageUrls([path]);
      if (!mounted) return;
      setState(() {
        _imagePaths.add(path);
        _signedUrls.addAll(signed);
      });
      showAppToast(context, '图片已上传');
    } catch (e) {
      if (mounted) showAppToast(context, friendlyError(e), isError: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _pickIngredientToAdd() async {
    final available = _ingredients
        .where((i) => !_recipeRows.any((r) => r.ingredient.id == i.id))
        .toList();
    if (available.isEmpty) {
      showAppToast(context, '所有食材都已添加，或请先去食材仓库新增食材');
      return;
    }
    final selected = await showCupertinoModalPopup<Ingredient>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('选择每份菜需要的食材'),
        actions: available
            .map(
              (i) => CupertinoActionSheetAction(
                onPressed: () => Navigator.pop(ctx, i),
                child: Text('${i.name}（${i.unit}）'),
              ),
            )
            .toList(),
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
      ),
    );
    if (selected != null && mounted) {
      setState(() {
        _recipeRows.add(_RecipeRow(
          ingredient: selected,
          amountCtrl: TextEditingController(text: '1'),
        ));
      });
    }
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = '请输入菜品名称');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final backend = AppStateScope.read(context).backend;
      Dish saved;
      if (_isEdit) {
        saved = await backend.updateDish(
          widget.existing!.id,
          categoryId: _categoryId,
          clearCategory: _categoryId == null,
          name: name,
          description: _descCtrl.text.trim(),
          recipe: _recipeCtrl.text.trim(),
          imagePaths: _imagePaths,
          tags: _tags,
          isPublic: _isPublic,
          isRecipePublic: _isRecipePublic,
          isAvailable: _isAvailable,
        );
      } else {
        saved = await backend.createDish(
          kitchenId: widget.kitchenId,
          categoryId: _categoryId,
          name: name,
          description: _descCtrl.text.trim(),
          recipe: _recipeCtrl.text.trim(),
          imagePaths: _imagePaths,
          tags: _tags,
          isPublic: _isPublic,
          isRecipePublic: _isRecipePublic,
          isAvailable: _isAvailable,
        );
      }

      final recipePayload = _recipeRows
          .map((r) => DishIngredient(
                kitchenId: widget.kitchenId,
                dishId: saved.id,
                ingredientId: r.ingredient.id,
                amount: double.tryParse(r.amountCtrl.text.trim()) ?? 0,
              ))
          .where((r) => r.amount > 0)
          .toList();
      await backend.replaceDishIngredients(saved.id, widget.kitchenId, recipePayload);

      if (!mounted) return;
      showAppToast(context, _isEdit ? '菜品已保存' : '菜品已添加');
      Navigator.of(context).pop(saved);
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text('删除「${widget.existing!.name}」？'),
        content: const Text('删除后无法恢复。'),
        actions: [
          CupertinoDialogAction(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await AppStateScope.read(context).backend.deleteDish(widget.existing!.id);
      if (!mounted) return;
      showAppToast(context, '已删除菜品');
      Navigator.of(context).pop('deleted');
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? '编辑菜品' : '新增菜品')),
      body: _loading
          ? const Center(child: CupertinoActivityIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
              children: [
                if (_error != null) InfoBanner(message: _error!),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _nameCtrl,
                        maxLength: 40,
                        decoration: const InputDecoration(
                          labelText: '菜名',
                          hintText: '例如：红烧排骨',
                          counterText: '',
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int?>(
                        initialValue: _categoryId,
                        decoration: const InputDecoration(labelText: '所属分类'),
                        items: [
                          const DropdownMenuItem<int?>(value: null, child: Text('未分类')),
                          ..._categories.map(
                            (c) => DropdownMenuItem<int?>(value: c.id, child: Text(c.name)),
                          ),
                        ],
                        onChanged: (v) => setState(() => _categoryId = v),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _descCtrl,
                        maxLines: 2,
                        maxLength: 200,
                        decoration: const InputDecoration(
                          labelText: '一句话简介（选填）',
                          hintText: '口味、分量、适合什么场合',
                          counterText: '',
                        ),
                      ),
                    ],
                  ),
                ),

                const SectionHeader(title: '标签（最多 12 个）'),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_tags.isNotEmpty) ...[
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _tags
                              .map(
                                (t) => InputChip(
                                  label: Text(t),
                                  backgroundColor: AppColors.primaryLight,
                                  labelStyle: const TextStyle(color: AppColors.primary, fontSize: 13),
                                  deleteIconColor: AppColors.primary,
                                  side: const BorderSide(color: AppColors.primaryBorder),
                                  onDeleted: () => setState(() => _tags.remove(t)),
                                ),
                              )
                              .toList(),
                        ),
                        const SizedBox(height: 10),
                      ],
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _tagInputCtrl,
                              maxLength: 12,
                              decoration: const InputDecoration(
                                hintText: '输入标签，如：微辣、下饭',
                                counterText: '',
                              ),
                              onSubmitted: _addTag,
                            ),
                          ),
                          const SizedBox(width: 8),
                          CupertinoButton(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            color: AppColors.primaryLight,
                            onPressed: () => _addTag(_tagInputCtrl.text),
                            child: const Text('添加', style: TextStyle(color: AppColors.primary, fontSize: 14)),
                          ),
                        ],
                      ),
                      if (_tagSuggestions.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: _tagSuggestions
                              .where((s) => !_tags.contains(s.name))
                              .take(8)
                              .map(
                                (s) => GestureDetector(
                                  onTap: () => _addTag(s.name),
                                  child: SmallTag(
                                    label: '+ ${s.name}',
                                    bg: AppColors.mutedBg,
                                    fg: AppColors.textSecondary,
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ],
                  ),
                ),

                SectionHeader(title: '菜品图片（${_imagePaths.length}/9）'),
                AppCard(
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (var i = 0; i < _imagePaths.length; i++)
                        Stack(
                          children: [
                            DishCover(
                              imageUrl: _signedUrls[_imagePaths[i]],
                              initial: '${i + 1}',
                              size: 78,
                              radius: 12,
                            ),
                            Positioned(
                              right: 2,
                              top: 2,
                              child: GestureDetector(
                                onTap: () => setState(() => _imagePaths.removeAt(i)),
                                child: Container(
                                  width: 22,
                                  height: 22,
                                  decoration: const BoxDecoration(
                                    color: Colors.black54,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(CupertinoIcons.xmark, color: Colors.white, size: 12),
                                ),
                              ),
                            ),
                          ],
                        ),
                      if (_imagePaths.length < 9)
                        GestureDetector(
                          onTap: _pickImage,
                          child: Container(
                            width: 78,
                            height: 78,
                            decoration: BoxDecoration(
                              color: AppColors.surfaceSoft,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: _uploading
                                ? const Center(child: CupertinoActivityIndicator())
                                : const Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(CupertinoIcons.photo_on_rectangle, color: AppColors.textSecondary, size: 22),
                                      SizedBox(height: 4),
                                      Text('上传图片', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                                    ],
                                  ),
                          ),
                        ),
                    ],
                  ),
                ),

                const SectionHeader(title: '每份用料（自动算库存是否足够）'),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_recipeRows.isEmpty)
                        const Text(
                          '不挂用料时，这道菜默认始终可点、不做库存拦截。',
                          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                        )
                      else
                        ..._recipeRows.asMap().entries.map((entry) {
                          final idx = entry.key;
                          final row = entry.value;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${row.ingredient.name}（${row.ingredient.unit}）',
                                    style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500),
                                  ),
                                ),
                                SizedBox(
                                  width: 88,
                                  child: TextField(
                                    controller: row.amountCtrl,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    textAlign: TextAlign.center,
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(CupertinoIcons.minus_circle, color: AppColors.danger, size: 20),
                                  onPressed: () {
                                    setState(() {
                                      row.amountCtrl.dispose();
                                      _recipeRows.removeAt(idx);
                                    });
                                  },
                                ),
                              ],
                            ),
                          );
                        }),
                      const SizedBox(height: 8),
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        color: AppColors.primaryLight,
                        onPressed: _pickIngredientToAdd,
                        child: const Text('+ 添加食材用量', style: TextStyle(color: AppColors.primary, fontSize: 14)),
                      ),
                    ],
                  ),
                ),

                const SectionHeader(title: '菜谱步骤'),
                AppCard(
                  child: TextField(
                    controller: _recipeCtrl,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      hintText: '写下用料、火候和步骤，朋友也能学着做…',
                    ),
                  ),
                ),

                const SectionHeader(title: '可见性与状态'),
                AppCard(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Column(
                    children: [
                      _switchTile('在菜单里公开', '关闭后仅厨房成员可见', _isPublic, (v) => setState(() => _isPublic = v)),
                      const Divider(),
                      _switchTile('公开菜谱', '关闭后别人只看菜名，看不到做法', _isRecipePublic, (v) => setState(() => _isRecipePublic = v)),
                      const Divider(),
                      _switchTile('今日在售', '关闭后标注为「已下架」', _isAvailable, (v) => setState(() => _isAvailable = v)),
                    ],
                  ),
                ),

                const SizedBox(height: 20),
                PrimaryPillButton(
                  label: _isEdit ? '保存菜品' : '添加到菜单',
                  loading: _saving || _uploading,
                  onPressed: _save,
                ),
                if (_isEdit) ...[
                  const SizedBox(height: 12),
                  GhostPillButton(
                    label: '删除这道菜',
                    danger: true,
                    onPressed: _saving ? null : _delete,
                  ),
                ],
              ],
            ),
    );
  }

  Widget _switchTile(String title, String sub, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                Text(sub, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
              ],
            ),
          ),
          CupertinoSwitch(
            value: value,
            activeTrackColor: AppColors.primary,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _RecipeRow {
  final Ingredient ingredient;
  final TextEditingController amountCtrl;

  _RecipeRow({required this.ingredient, required this.amountCtrl});
}
