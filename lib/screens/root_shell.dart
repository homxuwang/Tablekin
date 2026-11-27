import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'chef_screen.dart';
import 'home_screen.dart';
import 'orders_screen.dart';
import 'settings_screen.dart';

class RootShell extends StatelessWidget {
  const RootShell({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.of(context);

    if (!state.initialized) {
      return const Scaffold(
        body: Center(child: CupertinoActivityIndicator(radius: 14)),
      );
    }

    // If user switched to Supabase cloud but hasn't signed in yet, show Settings/Auth directly
    if (state.isCloud && !state.isSignedIn) {
      return const SettingsScreen();
    }

    final badge = state.totalOrdersBadge;

    return Scaffold(
      body: IndexedStack(
        index: state.tabIndex,
        children: const [
          HomeScreen(),
          ChefScreen(),
          OrdersScreen(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Color(0xFAFFFFFF),
          border: Border(top: BorderSide(color: AppColors.border, width: 0.7)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 58,
            child: Row(
              children: [
                _tabItem(
                  context,
                  index: 0,
                  icon: CupertinoIcons.book,
                  activeIcon: CupertinoIcons.book_fill,
                  label: '点菜',
                  active: state.tabIndex == 0,
                ),
                _tabItem(
                  context,
                  index: 1,
                  icon: CupertinoIcons.flame,
                  activeIcon: CupertinoIcons.flame_fill,
                  label: '下厨',
                  active: state.tabIndex == 1,
                ),
                _tabItem(
                  context,
                  index: 2,
                  icon: CupertinoIcons.doc_text,
                  activeIcon: CupertinoIcons.doc_text_fill,
                  label: '订单',
                  active: state.tabIndex == 2,
                  badge: badge,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tabItem(
    BuildContext context, {
    required int index,
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required bool active,
    int badge = 0,
  }) {
    final color = active ? AppColors.primary : AppColors.textMuted;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          AppStateScope.read(context).setTab(index);
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(active ? activeIcon : icon, color: color, size: 23),
                if (badge > 0)
                  Positioned(
                    right: -10,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      constraints: const BoxConstraints(minWidth: 16),
                      decoration: BoxDecoration(
                        color: AppColors.danger,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        badge > 99 ? '99+' : '$badge',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
