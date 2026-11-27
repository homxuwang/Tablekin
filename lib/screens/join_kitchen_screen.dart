import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/error_messages.dart';
import '../widgets/common_widgets.dart';
import 'menu_screen.dart';

class JoinKitchenScreen extends StatefulWidget {
  final String initialCode;

  const JoinKitchenScreen({super.key, this.initialCode = ''});

  @override
  State<JoinKitchenScreen> createState() => _JoinKitchenScreenState();
}

class _JoinKitchenScreenState extends State<JoinKitchenScreen> {
  late final TextEditingController _codeCtrl;
  final _nickCtrl = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _codeCtrl = TextEditingController(text: widget.initialCode);
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _nickCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) {
      setState(() => _error = '请输入邀请码');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final state = AppStateScope.read(context);
      final kitchen = await state.backend.joinKitchenByCode(
        code,
        nickname: _nickCtrl.text.trim(),
      );
      await state.refreshBadges();
      if (!mounted) return;
      showAppToast(context, '已加入「${kitchen.name}」');
      Navigator.of(context).pushReplacement(
        CupertinoPageRoute(builder: (_) => MenuScreen(kitchenId: kitchen.id)),
      );
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDemo = !AppStateScope.of(context).isCloud;
    return Scaffold(
      appBar: AppBar(title: const Text('加入朋友的厨房')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_error != null) InfoBanner(message: _error!),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '输入好友分享的邀请码',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                const Text(
                  '加入后就能成为厨房共有人，一起管理菜品、库存和接单，也能随时浏览私密菜单。',
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.5),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _codeCtrl,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: '邀请码',
                    hintText: '例如：MING2026',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _nickCtrl,
                  maxLength: 12,
                  decoration: const InputDecoration(
                    labelText: '你在厨房里的称呼（选填）',
                    hintText: '例如：小明、表姐',
                    counterText: '',
                  ),
                ),
                if (isDemo) ...[
                  const SizedBox(height: 10),
                  const Text(
                    '提示：体验模式可试输 MING2026（阿明的小灶）或 RAIN6666（小雨家周末饭局）',
                    style: TextStyle(fontSize: 12, color: AppColors.primary),
                  ),
                ],
                const SizedBox(height: 18),
                PrimaryPillButton(
                  label: '加入厨房',
                  loading: _submitting,
                  onPressed: _submit,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
