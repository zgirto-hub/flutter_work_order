import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/pwa_update_stub.dart'
    if (dart.library.js_interop) '../services/pwa_update_web.dart';
import '../theme/app_theme.dart';
import '../config.dart';
import '../widgets/claude_widgets.dart';
import '../services/activity_log_service.dart';
import '../services/user_service.dart';
import '../models/activity_log_entry.dart';
import 'system_status_screen.dart';

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
  State<DashboardScreen> createState() => DashboardScreenState();
}

class DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {

  bool _loading = true;
  bool _refreshing = false;
  int _openWorkOrders = 0;
  int _inProgressWorkOrders = 0;
  int _inspectionsToday = 0;
  List<ActivityLogEntry> _recentActivity = [];
  String _appVersion = '';
  String _appBuild = '';
  bool _checkingUpdate = false;
  String _updateMessage = '';
  bool _updateAvailable = false;
  Timer? _swPollTimer;
  bool _recentJustLoaded = false;
  String _displayName = '';

  String get _email =>
      Supabase.instance.client.auth.currentUser?.email ?? '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _loadVersion();
    _startSwUpdatePoll();
  }

  void _startSwUpdatePoll() {
    if (!kIsWeb || _updateAvailable) return;
    _swPollTimer?.cancel();
    _swPollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (checkSwUpdate() && mounted) {
        setState(() {
          _updateAvailable = true;
          _updateMessage = 'A new version is ready to install';
        });
        _swPollTimer?.cancel();
      }
    });
  }

  @override
  void dispose() {
    _swPollTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_loading) {
      _load();
      if (!_updateAvailable) _startSwUpdatePoll();
    }
  }

  void refresh() {
    if (!_loading) {
      setState(() => _refreshing = true);
      _load();
    }
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _appVersion = info.version;
        _appBuild = info.buildNumber;
      });
    }
  }

  Future<void> _load() async {
    if (!_refreshing) {
      setState(() => _loading = true);
    }
    try {
      await Future.wait([
        _loadWorkOrderStats(),
        _loadRecentActivity(),
        _loadUserName(),
      ]);
    } catch (_) {}
    if (mounted) {
      setState(() {
        _loading = false;
        _refreshing = false;
      });
    }
  }

  Future<void> _loadWorkOrderStats() async {
    try {
      final uri = Uri.parse('${AppConfig.baseUrl}/work-orders').replace(
        queryParameters: {
          'email': _email,
          'user_role': widget.userRole,
        },
      );
      final res = await http.get(uri);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final orders =
            (data['work_orders'] as List<dynamic>? ?? []);
        if (!mounted) return;
        setState(() {
          _openWorkOrders =
              orders.where((o) => o['status'] != 'Closed').length;
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

  Future<void> _loadUserName() async {
    try {
      final user = await UserService().fetchCurrentUser();
      if (!mounted || user == null) return;
      setState(() => _displayName = user.displayName);
    } catch (_) {}
  }

  Future<void> _loadRecentActivity() async {
    try {
      final logs = await ActivityLogService().fetchLogs(limit: 5);
      if (!mounted) return;
      setState(() {
        _recentActivity = logs;
        _recentJustLoaded = true;
      });
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) setState(() => _recentJustLoaded = false);
      });
    } catch (_) {}
  }

  Future<void> _checkUpdates() async {
    if (_checkingUpdate) return;
    setState(() {
      _checkingUpdate = true;
      _updateMessage = '';
      _updateAvailable = false;
    });

    final hasUpdate = kIsWeb && checkSwUpdate();

    if (mounted) {
      setState(() {
        _updateAvailable = hasUpdate;
        _updateMessage = hasUpdate
            ? 'A new version is ready to install'
            : 'You are on the latest version';
        _checkingUpdate = false;
      });
    }
  }

  void _applyUpdate() {
    if (kIsWeb) {
      applyPWAUpdate();
    }
  }

  Future<void> _signOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Sign out',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        content: Text(
          'Are you sure you want to sign out?',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Sign out',
                style: TextStyle(
                    color: Colors.red, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await Supabase.instance.client.auth.signOut();
    }
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
          onRefresh: () async {
            setState(() => _refreshing = true);
            await _load();
          },
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
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textTertiary,
                          ),
                        ),
                        Text(
                          _displayName.isNotEmpty
                            ? _displayName
                            : _email.split('@').first.split('.').first.capitalize(),
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                            letterSpacing: -0.4,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
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
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                        SizedBox(width: 8),
                        GestureDetector(
                          onTap: _refreshing ? null : () {
                            setState(() => _refreshing = true);
                            _load();
                          },
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: AppColors.bgSurface,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: AppColors.border, width: 0.5),
                            ),
                            child: _refreshing
                                ? SizedBox(
                                    width: 16, height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 1.5, color: AppColors.textTertiary))
                                : Icon(
                                    Icons.refresh_rounded,
                                    size: 16,
                                    color: AppColors.textTertiary,
                                  ),
                          ),
                        ),
                        SizedBox(width: 8),
                        GestureDetector(
                          onTap: _signOut,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: AppColors.bgSurface,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: AppColors.border, width: 0.5),
                            ),
                            child: Icon(
                              Icons.logout_rounded,
                              size: 16,
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                SizedBox(height: 20),

                // ── Stats row ──────────────────────────────────
                if (_loading)
                  Center(
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
                          label: 'Pending',
                          value: widget.openRequestCount,
                          icon: Icons.inbox_outlined,
                          color: AppColors.pendingText,
                          bgColor: AppColors.pendingBg,
                          onTap: () => widget.onNavigate(2),
                        ),
                      ),
                      SizedBox(width: 10),
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
                  SizedBox(height: 10),
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
                      if (widget.userRole != 'reporter') ...[
                        SizedBox(width: 10),
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
                    ],
                  ),

                  SizedBox(height: 24),

                  // ── Quick actions ──────────────────────────
                  SectionLabel(text: 'Quick Actions'),
                  SizedBox(height: 8),
                  _QuickAction(
                    label: 'New Work Order',
                    icon: Icons.add_circle_outline_rounded,
                    color: AppColors.accent,
                    onTap: () => widget.onNavigate(1),
                    trailing: Icon(Icons.chevron_right_rounded,
                        size: 16, color: AppColors.textTertiary),
                  ),
                  SizedBox(height: 10),
                  _QuickAction(
                    label: 'System Status',
                    icon: Icons.monitor_heart_outlined,
                    color: AppColors.accent,
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const SystemStatusScreen())),
                    trailing: Icon(Icons.chevron_right_rounded,
                        size: 16, color: AppColors.textTertiary),
                  ),
                  SizedBox(height: 10),
                  _QuickAction(
                    label: 'Check for update',
                    subtitle: 'v${_appVersion.isEmpty ? '...' : _appVersion} (Build ${_appBuild.isEmpty ? '...' : _appBuild})',
                    icon: Icons.system_update_outlined,
                    color: AppColors.accent,
                    onTap: _checkingUpdate ? null : _checkUpdates,
                    trailing: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: _checkingUpdate
                          ? SizedBox(
                              key: ValueKey('spinner'),
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 1.5, color: AppColors.textTertiary))
                          : Icon(Icons.chevron_right_rounded,
                              key: ValueKey('chevron'),
                              size: 16, color: AppColors.textTertiary),
                    ),
                  ),
                  AnimatedOpacity(
                    opacity: _updateMessage.isNotEmpty ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 250),
                    child: _updateMessage.isNotEmpty
                        ? Padding(
                            padding: const EdgeInsets.only(top: 8, left: 4),
                            child: Row(
                              children: [
                                Text(
                                  _updateMessage,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textTertiary,
                                  ),
                                ),
                                if (_updateAvailable) ...[
                                  SizedBox(width: 8),
                                  GestureDetector(
                                    onTap: _applyUpdate,
                                    child: Text(
                                      'Update now',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: AppColors.accent,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          )
                        : SizedBox.shrink(),
                  ),

                  SizedBox(height: 24),

                  // ── Recent activity ────────────────────────
                  Text(
                    'Recent Activity',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                      letterSpacing: -0.2,
                    ),
                  ),
                  SizedBox(height: 8),

                  if (_recentActivity.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppColors.bgSurface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: AppColors.border, width: 0.5),
                      ),
                      child: Center(
                        child: Text(
                          'No recent activity',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ),
                    )
                    else
                    AnimatedOpacity(
                      opacity: _recentJustLoaded ? 0.6 : 1.0,
                      duration: const Duration(milliseconds: 300),
                      child: Container(
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
                                _RecentActivityRow(entry: item),
                                if (!isLast)
                                  Divider(
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
            SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
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
  final String? subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final Widget? trailing;

  const _QuickAction({
    required this.label,
    this.subtitle,
    required this.icon,
    required this.color,
    this.onTap,
    this.trailing,
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
            SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (subtitle != null) ...[
                    SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 10,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              SizedBox(width: 8),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}

// ── Recent Activity Row ───────────────────────────────────────────────────────

class _RecentActivityRow extends StatelessWidget {
  final ActivityLogEntry entry;

  const _RecentActivityRow({required this.entry});

  IconData _actionIcon(String action, String category) {
    switch (action) {
      case 'signed_in':
        return Icons.login_rounded;
      case 'signed_out':
        return Icons.logout_rounded;
      case 'created':
        return Icons.add_circle_outline_rounded;
      case 'updated':
        return Icons.edit_outlined;
      case 'deleted':
        return Icons.delete_outline_rounded;
      case 'closed':
        return Icons.check_circle_outline_rounded;
      case 'uploaded':
        return Icons.upload_file_rounded;
      case 'role_changed':
        return Icons.swap_horiz_rounded;
      case 'password_reset':
      case 'password_reset_completed':
        return Icons.lock_reset_rounded;
      case 'user_created':
        return Icons.person_add_outlined;
      default:
        return Icons.circle_outlined;
    }
  }

  Color _actionColor(String action) {
    switch (action) {
      case 'created':
      case 'user_created':
        return AppColors.closedText;
      case 'deleted':
        return AppColors.dangerText;
      case 'signed_in':
      case 'signed_out':
        return AppColors.textTertiary;
      default:
        return AppColors.accent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = entry.targetLabel ?? '';
    final desc = entry.description;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: _actionColor(entry.action).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(_actionIcon(entry.action, entry.category),
                size: 15, color: _actionColor(entry.action)),
          ),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  desc,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (label.isNotEmpty) ...[
                  SizedBox(height: 2),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 10,
                      color: AppColors.textTertiary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          SizedBox(width: 8),
          Text(
            entry.formattedTime,
            style: TextStyle(
              fontSize: 10,
              color: AppColors.textTertiary,
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
