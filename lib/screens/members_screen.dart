import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/error_messages.dart';
import '../utils/meal_time.dart';
import '../widgets/common_widgets.dart';

class MembersScreen extends StatefulWidget {
  final int kitchenId;

  const MembersScreen({super.key, required this.kitchenId});

  @override
  State<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends State<MembersScreen> {
  Kitchen? _kitchen;
  KitchenInvite? _invite;
  List<KitchenMember> _members = [];
  bool _loading = true;
  bool _inviteBusy = false;
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
      final kitchen = await backend.fetchKitchen(widget.kitchenId);
      final members = await backend.fetchMembers(widget.kitchenId);
      KitchenInvite? invite;
      if (kitchen != null && kitchen.isOwner) {
        invite = await backend.getKitchenInvite(widget.kitchenId);
      }
      if (!mounted) return;
      setState(() {
        _kitchen = kitchen;
        _members = members;
        _invite = invite;
      });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resetInvite() async {
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('更换邀请码？'),
        content: const Text('换码后旧邀请码立即失效，已加入的成员不受影响。'),
        actions: [
          CupertinoDialogAction(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认更换'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _inviteBusy = true);
    try {
      final inv = await AppStateScope.read(context).backend.resetKitchenInvite(widget.kitchenId);
      if (mounted) {
        setState(() => _invite = inv);
        showAppToast(context, '已生成新邀请码：${inv.inviteCode}');
      }
    } catch (e) {
      if (mounted) showAppToast(context, friendlyError(e), isError: true);
    } finally {
      if (mounted) setState(() => _inviteBusy = false);
    }
  }

  Future<void> _renameMember(KitchenMember member) async {
    final ctrl = TextEditingController(text: member.nickname);
    final result = await showCupertinoDialog<String>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('修改称呼'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: CupertinoTextField(
            controller: ctrl,
            placeholder: '输入在厨房里的称呼',
            maxLength: 12,
          ),
        ),
        actions: [
          CupertinoDialogAction(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result == null || result.isEmpty || !mounted) return;
    try {
      await AppStateScope.read(context).backend.updateMemberNickname(member.id, result);
      await _load();
      if (mounted) showAppToast(context, '称呼已更新');
    } catch (e) {
      if (mounted) showAppToast(context, friendlyError(e), isError: true);
    }
  }

  Future<void> _removeMember(KitchenMember member, {bool isSelf = false}) async {
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(isSelf ? '退出这个厨房？' : '移出「${member.displayName}」？'),
        content: Text(isSelf ? '退出后将无法再管理这个厨房。' : '移出后对方不再是共有人，如需防止再次加入可更换邀请码。'),
        actions: [
          CupertinoDialogAction(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isSelf ? '退出' : '移出'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await AppStateScope.read(context).backend.removeMember(member.id);
      if (!mounted) return;
      if (isSelf) {
        showAppToast(context, '已退出厨房');
        Navigator.of(context).pop('left');
      } else {
        showAppToast(context, '已移出成员');
        await _load();
      }
    } catch (e) {
      if (mounted) showAppToast(context, friendlyError(e), isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.of(context);
    final myUid = state.currentUser?.id;
    final isOwner = _kitchen?.isOwner == true;
    final myRow = _members.where((m) => m.userId == myUid).firstOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('成员与邀请')),
      body: _loading
          ? const Center(child: CupertinoActivityIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                children: [
                  if (_error != null) InfoBanner(message: _error!),
                  if (isOwner && _invite != null) ...[
                    const SectionHeader(title: '邀请好友加入共管'),
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '把「${_kitchen?.name ?? '厨房'}」分享给家人朋友',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            '好友输入邀请码即可成为共有人，一起管理菜品、库存与接单。',
                            style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.45),
                          ),
                          const SizedBox(height: 14),
                          GestureDetector(
                            onTap: () {
                              Clipboard.setData(ClipboardData(text: _invite!.inviteCode));
                              HapticFeedback.lightImpact();
                              showAppToast(context, '邀请码 ${_invite!.inviteCode} 已复制');
                            },
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                              decoration: BoxDecoration(
                                color: AppColors.primaryLight,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: AppColors.primaryBorder),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    _invite!.inviteCode,
                                    style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 3,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  const Icon(CupertinoIcons.doc_on_doc, size: 18, color: AppColors.primary),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          PrimaryPillButton(
                            label: '分享邀请给好友',
                            icon: CupertinoIcons.share,
                            onPressed: _inviteBusy
                                ? null
                                : () {
                                    SharePlus.instance.share(
                                      ShareParams(
                                        text:
                                            '来「一桌人」加入我的厨房【${_kitchen?.name ?? ''}】一起做饭点菜吧！邀请码：${_invite!.inviteCode}',
                                      ),
                                    );
                                  },
                          ),
                          const SizedBox(height: 8),
                          Center(
                            child: CupertinoButton(
                              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                              onPressed: _inviteBusy ? null : _resetInvite,
                              child: Text(
                                _inviteBusy ? '正在更换…' : '换一个邀请码（旧码将失效）',
                                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  SectionHeader(title: '厨房成员（${_members.length}）'),
                  AppCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (var i = 0; i < _members.length; i++) ...[
                          if (i > 0) const Divider(indent: 68),
                          _buildMemberTile(_members[i], myUid, isOwner),
                        ],
                      ],
                    ),
                  ),

                  if (!isOwner && myRow != null) ...[
                    const SizedBox(height: 20),
                    GhostPillButton(
                      label: '退出这个厨房',
                      danger: true,
                      onPressed: () => _removeMember(myRow, isSelf: true),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildMemberTile(KitchenMember member, String? myUid, bool amOwner) {
    final isMe = member.userId == myUid;
    final canRemove = amOwner && !member.isOwner && !isMe;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          KitchenAvatar(initial: member.initial, size: 42, warm: member.isOwner),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      member.displayName,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 6),
                    SmallTag(
                      label: member.isOwner ? '主厨' : '共有人',
                      bg: member.isOwner ? AppColors.primaryLight : AppColors.mutedBg,
                      fg: member.isOwner ? AppColors.primary : AppColors.textSecondary,
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 4),
                      const SmallTag(label: '我', bg: AppColors.ackBg, fg: AppColors.ackText),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '加入于 ${formatMonthDay(member.createdAt)}',
                  style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          if (isMe)
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              onPressed: () => _renameMember(member),
              child: const Text('改称呼', style: TextStyle(fontSize: 13.5)),
            )
          else if (canRemove)
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              onPressed: () => _removeMember(member),
              child: const Text('移出', style: TextStyle(fontSize: 13.5, color: AppColors.danger)),
            ),
        ],
      ),
    );
  }
}
