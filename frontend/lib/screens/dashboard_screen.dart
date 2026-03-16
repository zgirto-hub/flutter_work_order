import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import '../config.dart';
import '../widgets/claude_widgets.dart';

class DashboardScreen extends StatefulWidget {
  final String userRole;
  final int openRequestCount;
  final ValueChanged<int> onNavigate;

  const DashboardScreen({
    super.key,
    required this.userRole,
    required this.openRequestCount,
    required this.onNavigate,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _loading = true;
  int _openWorkOrders = 0;
  int _pendingWorkOrders = 0;
  int _inProgressWorkOrders = 0;
  int _inspectionsToday = 0;
  List<Map<String, dynamic>> _recentActivity = [];

  String get _email =>
      Supabase.instance.client.auth.currentUser?.email ?? '';

  String get _firstName =>
      _email.split('@').first.split('.').first.capitalize();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      await Future.wait([
        _loadWorkOrderStats(),
        _loadRecentActivity(),
      ]);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadWorkOrderStats() async {
    try {
      final res =
          await http.get(Uri.parse('${AppConfig.baseUrl}/work-orders'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final orders =
            (data['work_orders'] as List<dynamic>? ?? []);
        if (!mounted) return;
        setState(() {
          _openWorkOrders =
              orders.where((o) => o['status'] != 'Closed').length;
          _pendingWorkOrders =
              orders.where((o) => o['status'] == 'Pending').length;
          _inProgressWorkOrders = orders
              .where((o) => o['status'] == 'In Progress')
              .length;
          _inspectionsToday = orders
              .where((o) =>
                  o['type'] == 'Inspection' &&
                  o['status'] != 'Closed')
              .length;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadRecentActivity() async {
    // Placeholder — will be populated when activity log is built
    // For now show recent work orders as activity
    try {
      final res =
          await http.get(Uri.parse('${AppConfig.baseUrl}/work-orders'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final orders =
            (data['work_orders'] as List<dynamic>? ?? []).take(5).toList();
        if (!mounted) return;
        setState(() {
          _recentActivity = orders
              .map((o) => {
                    'title': o['title'] ?? '',
                    'status': o['status'] ?? '',
                    'type': o['type'] ?? '',
                    'created_at': o['created_at'] ?? '',
                  })
              .toList();
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
            ? 'Good afternoon'
            : 'Good evening';

    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          color: AppColors.accent,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // ── Greeting ──────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$greeting,',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textTertiary,
                          ),
                        ),
                        Text(
                          _firstName,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                            letterSpacing: -0.4,
                          ),
                        ),
                      ],
                    ),
                    // Date badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.bgSurface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: AppColors.border, width: 0.5),
                      ),
                      child: Text(
                        _formatDate(DateTime.now()),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // ── Stats row ──────────────────────────────────
                if (_loading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: CircularProgressIndicator(
                          color: AppColors.accent, strokeWidth: 2),
                    ),
                  )
                else ...[
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          label: 'Open Requests',
                          value: widget.openRequestCount,
                          icon: Icons.inbox_outlined,
                          color: AppColors.pendingText,
                          bgColor: AppColors.pendingBg,
                          onTap: () => widget.onNavigate(2),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _StatCard(
                          label: 'Active Orders',
                          value: _openWorkOrders,
                          icon: Icons.work_outline_rounded,
                          color: AppColors.inProgressText,
                          bgColor: AppColors.inProgressBg,
                          onTap: () => widget.onNavigate(1),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          label: 'In Progress',
                          value: _inProgressWorkOrders,
                          icon: Icons.pending_outlined,
                          color: AppColors.accent,
                          bgColor: AppColors.accentBg,
                          onTap: () => widget.onNavigate(1),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _StatCard(
                          label: 'Inspections',
                          value: _inspectionsToday,
                          icon: Icons.checklist_rounded,
                          color: AppColors.closedText,
                          bgColor: AppColors.closedBg,
                          onTap: () => widget.onNavigate(1),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // ── Quick actions ──────────────────────────
                  SectionLabel(text: 'Quick Actions'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _QuickAction(
                          label: 'New Work Order',
                          icon: Icons.add_circle_outline_rounded,
                          color: AppColors.accent,
                          onTap: () => widget.onNavigate(1),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _QuickAction(
                          label: 'New Request',
                          icon: Icons.inbox_outlined,
                          color: AppColors.inProgressText,
                          onTap: () => widget.onNavigate(2),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // ── Recent work orders ─────────────────────
                  Row(
                    mainAxisAlignment:
                        MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Recent Work Orders',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                          letterSpacing: -0.2,
                        ),
                      ),
                      GestureDetector(
                        onTap: () => widget.onNavigate(1),
                        child: const Text(
                          'See all',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.accent,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  if (_recentActivity.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppColors.bgSurface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: AppColors.border, width: 0.5),
                      ),
                      child: const Center(
                        child: Text(
                          'No recent work orders',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ),
                    )
                  else
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.bgSurface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: AppColors.border, width: 0.5),
                      ),
                      child: Column(
                        children: _recentActivity
                            .asMap()
                            .entries
                            .map((entry) {
                          final i = entry.key;
                          final item = entry.value;
                          final isLast = i ==
                              _recentActivity.length - 1;
                          return Column(
                            children: [
                              _RecentActivityRow(item: item),
                              if (!isLast)
                                const Divider(
                                  height: 0,
                                  thickness: 0.5,
                                  color: AppColors.border,
                                  indent: 14,
                                  endIndent: 14,
                                ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }
}

// ── Stat Card ─────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;
  final Color color;
  final Color bgColor;
  final VoidCallback onTap;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.bgColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.bgSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(icon, size: 16, color: color),
                ),
                Text(
                  '$value',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: color,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Quick Action ──────────────────────────────────────────────────────────────

class _QuickAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _QuickAction({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
        decoration: BoxDecoration(
          color: AppColors.bgSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Recent Activity Row ───────────────────────────────────────────────────────

class _RecentActivityRow extends StatelessWidget {
  final Map<String, dynamic> item;

  const _RecentActivityRow({required this.item});

  Color _statusColor(String status) {
    switch (status) {
      case 'Pending':
        return AppColors.pendingText;
      case 'In Progress':
        return AppColors.inProgressText;
      case 'Closed':
        return AppColors.closedText;
      default:
        return AppColors.textTertiary;
    }
  }

  Color _statusBg(String status) {
    switch (status) {
      case 'Pending':
        return AppColors.pendingBg;
      case 'In Progress':
        return AppColors.inProgressBg;
      case 'Closed':
        return AppColors.closedBg;
      default:
        return AppColors.bgSurface2;
    }
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'Inspection':
        return Icons.checklist_rounded;
      default:
        return Icons.work_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = item['status'] as String? ?? '';
    final type = item['type'] as String? ?? '';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.bgSurface2,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(_typeIcon(type),
                size: 15, color: AppColors.textSecondary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              item['title'] as String? ?? '',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _statusBg(status),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              status,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: _statusColor(status),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── String extension ──────────────────────────────────────────────────────────

extension StringCapitalize on String {
  String capitalize() {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1)}';
  }
}
