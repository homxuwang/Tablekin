import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/error_messages.dart';
import '../widgets/common_widgets.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _urlCtrl = TextEditingController();
  final _keyCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();

  bool _isSignUp = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = AppStateScope.read(context);
      _urlCtrl.text = state.supabaseUrl;
      _keyCtrl.text = state.supabaseAnonKey;
    });
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _keyCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _connectSupabase() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AppStateScope.read(context)
          .configureAndSwitchToSupabase(_urlCtrl.text, _keyCtrl.text);
      if (mounted) showAppToast(context, '已切换到 Supabase 云端模式');
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _switchToDemo() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AppStateScope.read(context).switchToDemo();
      if (mounted) showAppToast(context, '已切换到本地体验模式');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitAuth() async {
    final email = _emailCtrl.text.trim();
    final pwd = _passwordCtrl.text;
    if (email.isEmpty || pwd.isEmpty) {
      setState(() => _error = '请输入邮箱和密码');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final state = AppStateScope.read(context);
      if (_isSignUp) {
        await state.signUp(email, pwd, displayName: _nameCtrl.text.trim());
        if (mounted) showAppToast(context, '注册并登录成功');
      } else {
        await state.signIn(email, pwd);
        if (mounted) showAppToast(context, '登录成功');
      }
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _simulateOrder() async {
    final state = AppStateScope.read(context);
    final order = await state.backend.simulateFriendOrder();
    if (!mounted) return;
    if (order == null) {
      showAppToast(context, '请先创建一个包含菜品的厨房', isError: true);
    } else {
      await state.refreshBadges();
      if (mounted) {
        showAppToast(context, '${order.dinerName} 刚给你点了：${order.dishesSummary}');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.of(context);
    final user = state.currentUser;

    return Scaffold(
      appBar: AppBar(title: const Text('账号与云端连接')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          if (_error != null) InfoBanner(message: _error!),
          AppCard(
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: state.isCloud ? AppColors.doingBg : AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    state.isCloud ? CupertinoIcons.cloud_fill : CupertinoIcons.sparkles,
                    color: state.isCloud ? AppColors.doingText : AppColors.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        state.backend.backendName,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        user != null
                            ? '当前身份：${user.displayName} (${user.email})'
                            : '未登录，请在下方登录 Supabase 账号',
                        style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          if (!state.isCloud) ...[
            const SectionHeader(title: '互动演示工具'),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '单台 iPhone 即可体验完整互点与接单流程',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '点击下方按钮，模拟朋友向「我的私房小厨」发来一笔新点单，随后可到「订单 → 我收到的」体验回执、接单自动扣库存与出餐。',
                    style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.5),
                  ),
                  const SizedBox(height: 14),
                  PrimaryPillButton(
                    label: '模拟好友来点一单',
                    icon: CupertinoIcons.bell_fill,
                    onPressed: _simulateOrder,
                  ),
                ],
              ),
            ),
          ],

          const SectionHeader(title: 'Supabase 云端同步（推荐好友互点方案）'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '为什么优先推荐 Supabase？',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                const Text(
                  '• 内置 PostgreSQL 行级锁事务：接单扣库存与并发盘点零冲突\n'
                  '• 内置 Realtime 实时同步：好友一点菜，大厨 iPhone 即刻更新\n'
                  '• 仓库已附带 supabase/migrations/001_init.sql 一键建表脚本',
                  style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.55),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _urlCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Supabase Project URL',
                    hintText: 'https://xxxx.supabase.co',
                  ),
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _keyCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Supabase Anon Key',
                    hintText: 'eyJhbGciOi...',
                  ),
                ),
                const SizedBox(height: 14),
                PrimaryPillButton(
                  label: state.isCloud ? '更新云端配置' : '连接 Supabase 云端',
                  loading: _busy,
                  onPressed: _connectSupabase,
                ),
                if (state.isCloud) ...[
                  const SizedBox(height: 10),
                  GhostPillButton(
                    label: '切回本地体验模式',
                    onPressed: _busy ? null : _switchToDemo,
                  ),
                ],
              ],
            ),
          ),

          if (state.isCloud) ...[
            const SectionHeader(title: 'Supabase 账号'),
            AppCard(
              child: user != null
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('已登录：${user.email}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                        const SizedBox(height: 14),
                        GhostPillButton(
                          label: '退出登录',
                          danger: true,
                          onPressed: _busy
                              ? null
                              : () async {
                                  await state.signOut();
                                  if (context.mounted) showAppToast(context, '已退出登录');
                                },
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CupertinoSlidingSegmentedControl<bool>(
                          groupValue: _isSignUp,
                          children: const {
                            false: Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('登录')),
                            true: Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('注册新账号')),
                          },
                          onValueChanged: (v) {
                            if (v != null) setState(() => _isSignUp = v);
                          },
                        ),
                        const SizedBox(height: 14),
                        if (_isSignUp) ...[
                          TextField(
                            controller: _nameCtrl,
                            decoration: const InputDecoration(labelText: '昵称（选填）', hintText: '如：小明'),
                          ),
                          const SizedBox(height: 10),
                        ],
                        TextField(
                          controller: _emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(labelText: '邮箱', hintText: 'you@example.com'),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _passwordCtrl,
                          obscureText: true,
                          decoration: const InputDecoration(labelText: '密码', hintText: '至少 6 位'),
                        ),
                        const SizedBox(height: 14),
                        PrimaryPillButton(
                          label: _isSignUp ? '注册并登录' : '登录',
                          loading: _busy,
                          onPressed: _submitAuth,
                        ),
                      ],
                    ),
            ),
          ],
        ],
      ),
    );
  }
}
