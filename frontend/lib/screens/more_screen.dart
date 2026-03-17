import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import '../widgets/claude_widgets.dart';
import '../services/notification_service.dart';
import '../screens/Documents/documents_screen.dart';
import '../screens/reports/workorder_report_screen.dart';
import '../screens/settings_page.dart';
import '../screens/settings/activity_log_screen.dart';
import '../screens/notifications_screen.dart';

class MoreScreen extends StatefulWidget {
  final ThemeController themeController;
  final String userRole;

  const MoreScreen({
    super.key,
    required this.themeController,
    required this.userRole,
  });

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
  final _notificationService = NotificationService();
  int _unreadCount = 0;

  @override
  void initState() {
    super.initState();
    _loadUnreadCount();
  }

  Future<void> _loadUnreadCount() async {
    final count = await _notificationService.unreadCount();
    if (!mounted) return;
    setState(() => _unreadCount = count);
  }

  Future<void> _openNotifications() async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
    );
    await _loadUnreadCount();
  }

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
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'More',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: _openNotifications,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: AppColors.bgSurface2,
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(color: AppColors.border2, width: 0.5),
                          ),
                          child: Icon(
                            Icons.notifications_outlined,
                            size: 17,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        if (_unreadCount > 0)
                          Positioned(
                            top: -5,
                            right: -5,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: AppColors.accent,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                _unreadCount > 99 ? '99+' : '$_unreadCount',
                                style: const TextStyle(
                                  fontSize: 9,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            Divider(
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
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: 3.6,
                      ),
                      itemCount: items.length,
                      itemBuilder: (context, i) => _MoreCard(item: items[i]),
                    ),

                    SizedBox(height: 24),

                    // Settings section at bottom
                    SectionLabel(text: 'Account[1.0] & Settings'),
                    SizedBox(height: 8),
                    _SettingsTile(
                      themeController: widget.themeController,
                      userRole: widget.userRole,
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
        subtitle: _unreadCount > 0 ? '$_unreadCount unread' : 'Alerts & updates',
        icon: Icons.notifications_outlined,
        color: const Color(0xFFB45309),
        bgColor: const Color(0xFFFEF3C7),
        onTap: _openNotifications,
      ),
      if (widget.userRole == 'admin')
        _MoreItem(
          title: 'Activity Log',
          subtitle: 'User actions',
          icon: Icons.history_rounded,
          color: const Color(0xFF6B6860),
          bgColor: const Color(0xFFF5F4F0),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ActivityLogScreen()),
          ),
        ),
    ];

    return items;
  }

  void _comingSoon(BuildContext context, String name) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('$name - coming soon'),
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.textPrimary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.bgSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Row(
          children: [
            // Icon
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: item.bgColor,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(item.icon, size: 16, color: item.color),
            ),
            SizedBox(width: 10),
            // Text
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    item.title,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 1),
                  Text(
                    item.subtitle,
                    style: TextStyle(
                      fontSize: 10,
                      color: AppColors.textTertiary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            // Coming soon badge
            if (item.comingSoon)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.bgSurface2,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Soon',
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textTertiary,
                  ),
                ),
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
              child: Icon(Icons.settings_outlined,
                  size: 18, color: AppColors.textSecondary),
            ),
            SizedBox(width: 12),
            Expanded(
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
            Icon(Icons.chevron_right_rounded,
                size: 16, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}
