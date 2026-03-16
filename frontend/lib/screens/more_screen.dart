import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import '../widgets/claude_widgets.dart';
import '../screens/Documents/documents_screen.dart';
import '../screens/reports/workorder_report_screen.dart';
import '../screens/settings_page.dart';

class MoreScreen extends StatelessWidget {
  final ThemeController themeController;
  final String userRole;

  const MoreScreen({
    super.key,
    required this.themeController,
    required this.userRole,
  });

  @override
  Widget build(BuildContext context) {
    // Build grid items based on role
    final items = _buildItems(context);

    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ────────────────────────────────────
            Container(
              color: AppColors.bgSurface,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: const Row(
                children: [
                  Text(
                    'More',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
            ),

            const Divider(
                height: 0, thickness: 0.5, color: AppColors.border),

            // ── Grid ──────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Main grid
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 1.6,
                      ),
                      itemCount: items.length,
                      itemBuilder: (context, i) => _MoreCard(item: items[i]),
                    ),

                    const SizedBox(height: 24),

                    // Settings section at bottom
                    SectionLabel(text: 'Account[1.0] & Settings'),
                    const SizedBox(height: 8),
                    _SettingsTile(
                      themeController: themeController,
                      userRole: userRole,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<_MoreItem> _buildItems(BuildContext context) {
    final items = <_MoreItem>[
      _MoreItem(
        title: 'Documents',
        subtitle: 'Files & folders',
        icon: Icons.description_outlined,
        color: const Color(0xFF7C3AED),
        bgColor: const Color(0xFFF3F0FF),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => const DocumentsScreen()),
        ),
      ),
      _MoreItem(
        title: 'Reports',
        subtitle: 'Work order reports',
        icon: Icons.bar_chart_rounded,
        color: const Color(0xFF15803D),
        bgColor: const Color(0xFFDCFCE7),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => const WorkOrderReportScreen()),
        ),
      ),
      _MoreItem(
        title: 'Employees',
        subtitle: 'Manage team',
        icon: Icons.people_outline_rounded,
        color: const Color(0xFFCC785C),
        bgColor: const Color(0xFFF5EBE6),
        onTap: () => _comingSoon(context, 'Employees'),
        comingSoon: true,
      ),
      _MoreItem(
        title: 'Calendar',
        subtitle: 'Schedule & events',
        icon: Icons.calendar_month_outlined,
        color: const Color(0xFF1D4ED8),
        bgColor: const Color(0xFFDBEAFE),
        onTap: () => _comingSoon(context, 'Calendar'),
        comingSoon: true,
      ),
      _MoreItem(
        title: 'Notifications',
        subtitle: 'Alerts & updates',
        icon: Icons.notifications_outlined,
        color: const Color(0xFFB45309),
        bgColor: const Color(0xFFFEF3C7),
        onTap: () => _comingSoon(context, 'Notifications'),
        comingSoon: true,
      ),
      if (userRole == 'admin')
        _MoreItem(
          title: 'Activity Log',
          subtitle: 'User actions',
          icon: Icons.history_rounded,
          color: const Color(0xFF6B6860),
          bgColor: const Color(0xFFF5F4F0),
          onTap: () => _comingSoon(context, 'Activity Log'),
          comingSoon: true,
        ),
    ];

    return items;
  }

  void _comingSoon(BuildContext context, String name) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('$name — coming soon'),
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.textPrimary,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      duration: const Duration(seconds: 2),
    ));
  }
}

// ── More Item model ───────────────────────────────────────────────────────────

class _MoreItem {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Color bgColor;
  final VoidCallback onTap;
  final bool comingSoon;

  const _MoreItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.bgColor,
    required this.onTap,
    this.comingSoon = false,
  });
}

// ── More Card ─────────────────────────────────────────────────────────────────

class _MoreCard extends StatelessWidget {
  final _MoreItem item;

  const _MoreCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: item.onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.bgSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Icon container
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: item.bgColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(item.icon, size: 18, color: item.color),
                ),
                // Coming soon badge
                if (item.comingSoon)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.bgSurface2,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Soon',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.subtitle,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Settings Tile ─────────────────────────────────────────────────────────────

class _SettingsTile extends StatelessWidget {
  final ThemeController themeController;
  final String userRole;

  const _SettingsTile({
    required this.themeController,
    required this.userRole,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SettingsPage(
            themeController: themeController,
            userRole: userRole,
          ),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.bgSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.bgSurface2,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.settings_outlined,
                  size: 18, color: AppColors.textSecondary),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Settings',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Theme, account, updates',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                size: 16, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}
