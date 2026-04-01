import 'package:flutter/material.dart';
import '../screens/Files/files_screen.dart';
import '../screens/reports/workorder_report_screen.dart';
import '../screens/calendar/calendar_screen.dart';
import '../screens/document_registry/document_registry_screen.dart';
import '../screens/payment_certificate/payment_certificate_list_screen.dart';
import '../screens/system_status_screen.dart';
import '../screens/notifications_screen.dart';
import '../screens/settings/activity_log_screen.dart';

class NavScreen {
  final String key;
  final String title;
  final String subtitle;
  final IconData icon;
  final IconData selectedIcon;
  final Color color;
  final Color bgColor;

  const NavScreen({
    required this.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selectedIcon,
    required this.color,
    required this.bgColor,
  });
}

class NavScreenRegistry {
  NavScreenRegistry._();

  static const List<NavScreen> all = [
    NavScreen(
      key: 'files',
      title: 'Files',
      subtitle: 'Files & folders',
      icon: Icons.description_outlined,
      selectedIcon: Icons.description_rounded,
      color: Color(0xFF7C3AED),
      bgColor: Color(0xFFF3F0FF),
    ),
    NavScreen(
      key: 'reports',
      title: 'Reports',
      subtitle: 'Work order reports',
      icon: Icons.bar_chart_rounded,
      selectedIcon: Icons.bar_chart_rounded,
      color: Color(0xFF15803D),
      bgColor: Color(0xFFDCFCE7),
    ),
    NavScreen(
      key: 'calendar',
      title: 'Calendar',
      subtitle: 'Recurring inspections',
      icon: Icons.calendar_month_outlined,
      selectedIcon: Icons.calendar_month_rounded,
      color: Color(0xFF1D4ED8),
      bgColor: Color(0xFFDBEAFE),
    ),
    NavScreen(
      key: 'doc_registry',
      title: 'Doc Registry',
      subtitle: 'Document records',
      icon: Icons.edit_note_outlined,
      selectedIcon: Icons.edit_note_rounded,
      color: Color(0xFF0E7490),
      bgColor: Color(0xFFCFFAFE),
    ),
    NavScreen(
      key: 'payment_cert',
      title: 'Payment Cert',
      subtitle: 'شهادة الدفع',
      icon: Icons.receipt_long_outlined,
      selectedIcon: Icons.receipt_long_rounded,
      color: Color(0xFFB91C1C),
      bgColor: Color(0xFFFEE2E2),
    ),
    NavScreen(
      key: 'system_status',
      title: 'Status',
      subtitle: 'Infrastructure health',
      icon: Icons.monitor_heart_outlined,
      selectedIcon: Icons.monitor_heart_rounded,
      color: Color(0xFF0369A1),
      bgColor: Color(0xFFE0F2FE),
    ),
    NavScreen(
      key: 'notifications',
      title: 'Notifications',
      subtitle: 'Alerts & updates',
      icon: Icons.notifications_outlined,
      selectedIcon: Icons.notifications_rounded,
      color: Color(0xFFB45309),
      bgColor: Color(0xFFFEF3C7),
    ),
    NavScreen(
      key: 'activity_log',
      title: 'Activity Log',
      subtitle: 'User actions',
      icon: Icons.history_rounded,
      selectedIcon: Icons.history_rounded,
      color: Color(0xFF6B6860),
      bgColor: Color(0xFFF5F4F0),
    ),
  ];

  static NavScreen? get(String key) {
    for (final s in all) {
      if (s.key == key) return s;
    }
    return null;
  }

  static Widget widgetForKey(String key, {required String userRole}) {
    return switch (key) {
      'files' => const FilesScreen(),
      'reports' => const WorkOrderReportScreen(),
      'calendar' => CalendarScreen(userRole: userRole),
      'doc_registry' => const DocumentRegistryScreen(),
      'payment_cert' => const PaymentCertificateListScreen(),
      'system_status' => const SystemStatusScreen(),
      'notifications' => const NotificationsScreen(),
      'activity_log' => const ActivityLogScreen(),
      _ => const SizedBox.shrink(),
    };
  }
}
