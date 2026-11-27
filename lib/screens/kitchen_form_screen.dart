import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/error_messages.dart';
import '../widgets/common_widgets.dart';

class KitchenFormScreen extends StatefulWidget {
  final Kitchen? existing;

  const KitchenFormScreen({super.key, this.existing});

  @override
  State<KitchenFormScreen> createState() => _KitchenFormScreenState();
}

class _KitchenFormScreenState extends State<KitchenFormScreen> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _nickCtrl;
  bool _isPublic = true;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.existing?.name ?? '');
    _descCtrl = TextEditingController(text: widget.existing?.description ?? '');
    _nickCtrl = TextEditingController(text: widget.existing?.myNickname ?? '');
    _isPublic = widget.existing?.isPublic ?? true;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _nickCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = '请先给厨房起个名字');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final state = AppStateScope.read(context);
      if (_isEdit) {
        final updated = await state.backend.updateKitchen(
          widget.existing!.id,
          name: name,
          description: _descCtrl.text.trim(),
          isPublic: _isPublic,
        );
        if (!mounted) return;
        showAppToast(context, '厨房资料已更新');
        Navigator.of(context).pop(updated);
      } else {
        final created = await state.backend.createKitchen(
          name: name,
          description: _descCtrl.text.trim(),
          isPublic: _isPublic,
          nickname: _nickCtrl.text.trim(),
        );
        await state.refreshBadges();
        if (!mounted) return;
        showAppToast(context, '厨房「${created.name}」已开张');
        Navigator.of(context).pop(created);
      }
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('删除这个厨房？'),
        content: Text('删除「${widget.existing!.name}」后，菜单、食材和订单记录将一并移除且无法恢复。'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    try {
      final state = AppStateScope.read(context);
      await state.backend.deleteKitchen(widget.existing!.id);
      await state.refreshBadges();
      if (!mounted) return;
      showAppToast(context, '厨房已删除');
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
      appBar: AppBar(title: Text(_isEdit ? '厨房资料' : '新建厨房')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_error != null) InfoBanner(message: _error!),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _nameCtrl,
                  maxLength: 30,
                  decoration: const InputDecoration(
                    labelText: '厨房名称',
                    hintText: '例如：老王家的小灶',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _descCtrl,
                  maxLines: 3,
                  maxLength: 120,
                  decoration: const InputDecoration(
                    labelText: '简介（选填）',
                    hintText: '一句话说说你们家擅长做什么菜、什么时候开饭',
                    counterText: '',
                  ),
                ),
                if (!_isEdit) ...[
                  const SizedBox(height: 14),
                  TextField(
                    controller: _nickCtrl,
                    maxLength: 12,
                    decoration: const InputDecoration(
                      labelText: '你的主厨称呼（选填）',
                      hintText: '例如：大厨、妈妈',
                      counterText: '',
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('公开厨房', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                          SizedBox(height: 2),
                          Text(
                            '关闭后仅厨房成员可见，朋友需凭邀请码加入',
                            style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    CupertinoSwitch(
                      value: _isPublic,
                      activeTrackColor: AppColors.primary,
                      onChanged: (v) => setState(() => _isPublic = v),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          PrimaryPillButton(
            label: _isEdit ? '保存修改' : '创建厨房',
            loading: _saving,
            onPressed: _save,
          ),
          if (_isEdit && widget.existing!.isOwner) ...[
            const SizedBox(height: 12),
            GhostPillButton(
              label: '删除厨房',
              danger: true,
              onPressed: _saving ? null : _delete,
            ),
          ],
        ],
      ),
    );
  }
}
