import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import '../widgets/claude_widgets.dart';
import '../services/notification_service.dart';
import '../screens/Files/files_screen.dart';
import '../screens/reports/workorder_report_screen.dart';
import '../screens/settings_page.dart';
import '../screens/settings/activity_log_screen.dart';
import '../screens/notifications_screen.dart';
import '../screens/calendar/calendar_screen.dart';
import '../screens/document_registry/document_registry_screen.dart';
import '../screens/payment_certificate/payment_certificate_list_screen.dart';
import '../screens/system_status_screen.dart';
import '../screens/approvals/pending_approvals_screen.dart';
import '../screens/letters_v2/letter_generator_screen_v2.dart';
import '../screens/manual_assistant/manual_assistant_screen.dart';
import '../models/nav_screen.dart';

class _TileCategory {
  final String label;
  final List<String> keys;
  const _TileCategory(this.label, this.keys);
}

const _categories = [
  _TileCategory('Documents & Files',
      ['files', 'doc_registry', 'payment_cert', 'letters_v2', 'manual_assistant']),
  _TileCategory(
      'Reports & Monitoring', ['reports', 'system_status', 'activity_log']),
  _TileCategory(
      'Scheduling & Approvals', ['calendar', 'approvals', 'notifications']),
];

class MoreScreen extends StatefulWidget {
  final ThemeController themeController;
  final String userRole;
  final List<String>? allowedScreens;
  final int approvalLevel;

  const MoreScreen({
    super.key,
    required this.themeController,
    required this.userRole,
    this.allowedScreens,
    this.approvalLevel = 0,
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
    widget.themeController.addListener(_onThemeChanged);
    _loadUnreadCount();
  }

  @override
  void dispose() {
    widget.themeController.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
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
                            border: Border.all(
                                color: AppColors.border2, width: 0.5),
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
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1),
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

            Divider(height: 0, thickness: 0.5, color: AppColors.border),

            // ── Categorised grid ─────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ..._buildCategorySections(context),

                    SizedBox(height: 24),

                    // Settings section at bottom
                    SectionLabel(text: 'Account & Settings'),
                    SizedBox(height: 8),
                    _SettingsTile(
                      themeController: widget.themeController,
                      userRole: widget.userRole,
                      allowedScreens: widget.allowedScreens,
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

  bool _canShow(String key) {
    if (key == 'approvals' && widget.approvalLevel == 0) return false;
    if (key == 'approvals' && widget.approvalLevel > 0) return true;
    if (widget.userRole == 'admin') return true;
    if (widget.allowedScreens == null) return true;
    return widget.allowedScreens!.contains(key);
  }

  Map<String, _MoreItem> _buildItemMap(BuildContext context) {
    final pinned = widget.themeController.pinnedNavScreens;
    final map = <String, _MoreItem>{};

    void add(String key, VoidCallback onTap, {String? subtitle}) {
      if (!_canShow(key)) return;
      final s = NavScreenRegistry.get(key);
      if (s == null) return;
      map[key] = _MoreItem(
        title: s.title,
        subtitle: subtitle ?? s.subtitle,
        icon: s.icon,
        color: s.color,
        bgColor: s.bgColor,
        onTap: onTap,
        isPinned: pinned.contains(s.key),
      );
    }

    add('files', () => Navigator.push(context,
        MaterialPageRoute(builder: (_) => const FilesScreen())));
    add('reports', () => Navigator.push(context,
        MaterialPageRoute(builder: (_) => const WorkOrderReportScreen())));
    add('calendar', () => Navigator.push(context,
        MaterialPageRoute(builder: (_) => CalendarScreen(userRole: widget.userRole))));
    add('doc_registry', () => Navigator.push(context,
        MaterialPageRoute(builder: (_) => const DocumentRegistryScreen())));
    add('payment_cert', () => Navigator.push(context,
        MaterialPageRoute(builder: (_) => const PaymentCertificateListScreen())));
    add('letters_v2', () => Navigator.push(context,
        MaterialPageRoute(builder: (_) => const LetterGeneratorScreenV2())));
    add('system_status', () => Navigator.push(context,
        MaterialPageRoute(builder: (_) => const SystemStatusScreen())));
    add('notifications', _openNotifications,
        subtitle: _unreadCount > 0 ? '$_unreadCount unread' : null);
    add('activity_log', () => Navigator.push(context,
        MaterialPageRoute(builder: (_) => const ActivityLogScreen())));
    add('approvals', () => Navigator.push(context,
        MaterialPageRoute(builder: (_) => const PendingApprovalsScreen())));
    add('manual_assistant', () => Navigator.push(context,
        MaterialPageRoute(builder: (_) => const ManualAssistantScreen())));

    return map;
  }

  List<Widget> _buildCategorySections(BuildContext context) {
    final itemMap = _buildItemMap(context);
    final sections = <Widget>[];

    for (final category in _categories) {
      final items = category.keys
          .where((key) => itemMap.containsKey(key))
          .map((key) => itemMap[key]!)
          .toList();

      if (items.isEmpty) continue;

      if (sections.isNotEmpty) {
        sections.add(const SizedBox(height: 24));
      }

      sections.add(SectionLabel(text: category.label));
      sections.add(const SizedBox(height: 8));
      sections.add(
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 2.8,
          ),
          itemCount: items.length,
          itemBuilder: (context, i) => _MoreCard(item: items[i]),
        ),
      );
    }

    return sections;
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
  final bool isPinned;

  const _MoreItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.bgColor,
    required this.onTap,
    this.isPinned = false,
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.bgSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Row(
          children: [
            // Icon
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: item.bgColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(item.icon, size: 18, color: item.color),
                ),
                if (item.isPinned)
                  Positioned(
                    top: -4,
                    right: -4,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Icon(Icons.push_pin_rounded,
                          size: 8, color: Colors.white),
                    ),
                  ),
              ],
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
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 2),
                  Text(
                    item.subtitle,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textTertiary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
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
  final List<String>? allowedScreens;

  const _SettingsTile({
    required this.themeController,
    required this.userRole,
    this.allowedScreens,
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
            allowedScreens: allowedScreens,
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
