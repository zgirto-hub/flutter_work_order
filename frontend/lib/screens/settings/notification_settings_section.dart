import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../theme/app_theme.dart';
import '../../config.dart';
import '../../services/onesignal_service.dart';
import '../../widgets/claude_widgets.dart';

class NotificationSettingsSection extends StatefulWidget {
  final String userRole;
  const NotificationSettingsSection({super.key, required this.userRole});

  @override
  State<NotificationSettingsSection> createState() =>
      _NotificationSettingsSectionState();
}

class _NotificationSettingsSectionState
    extends State<NotificationSettingsSection> {
  bool _notificationsEnabled = false;
  bool _adminAllWorkOrderComments = false;
  bool _savingAdminNotifPref = false;
  bool _techAutoAssignSelf = false;
  bool _savingTechAutoAssign = false;

  @override
  void initState() {
    super.initState();
    _notificationsEnabled = OneSignalService.isGranted();
    _loadNotificationPreferences();
  }

  Future<void> _loadNotificationPreferences() async {
    final email = Supabase.instance.client.auth.currentUser?.email;
    if (email == null || email.trim().isEmpty) return;
    try {
      final res = await http.get(
        Uri.parse(
          '${AppConfig.baseUrl}/notification-preferences?email=${Uri.encodeComponent(email.trim().toLowerCase())}',
        ),
      );
      if (res.statusCode != 200 || !mounted) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final prefs =
          (data['preferences'] as Map?)?.cast<String, dynamic>() ?? {};
      setState(() {
        _adminAllWorkOrderComments =
            prefs['admin_all_workorder_comments'] as bool? ?? false;
        _techAutoAssignSelf =
            prefs['technician_auto_assign_self'] as bool? ?? false;
      });
    } catch (_) {}
  }

  Future<void> _setAdminAllWorkOrderComments(bool enabled) async {
    final email = Supabase.instance.client.auth.currentUser?.email;
    if (email == null || email.trim().isEmpty || _savingAdminNotifPref) return;

    setState(() => _savingAdminNotifPref = true);
    try {
      final res = await http.patch(
        Uri.parse('${AppConfig.baseUrl}/notification-preferences'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email.trim().toLowerCase(),
          'admin_all_workorder_comments': enabled,
        }),
      );
      if (res.statusCode == 200 && mounted) {
        setState(() => _adminAllWorkOrderComments = enabled);
      }
    } catch (_) {}
    if (mounted) setState(() => _savingAdminNotifPref = false);
  }

  Future<void> _setTechAutoAssignSelf(bool enabled) async {
    final email = Supabase.instance.client.auth.currentUser?.email;
    if (email == null || email.trim().isEmpty || _savingTechAutoAssign) return;

    setState(() => _savingTechAutoAssign = true);
    try {
      final res = await http.patch(
        Uri.parse('${AppConfig.baseUrl}/notification-preferences'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email.trim().toLowerCase(),
          'technician_auto_assign_self': enabled,
        }),
      );
      if (res.statusCode == 200 && mounted) {
        setState(() => _techAutoAssignSelf = enabled);
      }
    } catch (_) {}
    if (mounted) setState(() => _savingTechAutoAssign = false);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(text: 'Notifications'),
        SurfaceCard(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Column(
            children: [
              SettingsRow(
                icon: _notificationsEnabled
                    ? Icons.notifications_active_outlined
                    : Icons.notifications_outlined,
                label: 'Push notifications',
                subtitle: widget.userRole == 'reporter'
                    ? 'Get updates on your work orders and comments'
                    : 'Get request and work order update notifications',
                showDivider:
                    widget.userRole == 'admin' || widget.userRole == 'technician',
                trailing: Switch(
                  value: _notificationsEnabled,
                  onChanged: (v) async {
                    final messenger = ScaffoldMessenger.of(context);
                    if (!v) {
                      try {
                        await OneSignalService.unsubscribe();
                      } catch (_) {}
                      setState(() => _notificationsEnabled = false);
                      messenger.showSnackBar(SnackBar(
                        content: Text('Notifications disabled'),
                        backgroundColor: AppColors.dangerText,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ));
                    } else {
                      bool granted = false;
                      try {
                        granted = await OneSignalService.requestPermission();
                      } catch (_) {}
                      setState(() => _notificationsEnabled = granted);
                      messenger.showSnackBar(SnackBar(
                        content: Text(granted
                            ? 'Notifications enabled!'
                            : 'Notifications blocked - check browser settings'),
                        backgroundColor:
                            granted ? AppColors.closedText : AppColors.dangerText,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ));
                    }
                  },
                ),
              ),
              if (widget.userRole == 'admin')
                SettingsRow(
                  icon: Icons.campaign_outlined,
                  label: 'Receive all work order comments',
                  subtitle: 'Get notified for every work order comment',
                  showDivider: false,
                  trailing: Switch(
                    value: _adminAllWorkOrderComments,
                    onChanged: _savingAdminNotifPref
                        ? null
                        : (v) => _setAdminAllWorkOrderComments(v),
                  ),
                  onTap: _savingAdminNotifPref
                      ? null
                      : () => _setAdminAllWorkOrderComments(
                            !_adminAllWorkOrderComments,
                          ),
                ),
              if (widget.userRole == 'technician')
                SettingsRow(
                  icon: Icons.assignment_ind_outlined,
                  label: 'Auto-assign me to my work orders',
                  subtitle: 'Automatically assign yourself to WOs you create',
                  showDivider: false,
                  trailing: Switch(
                    value: _techAutoAssignSelf,
                    onChanged: _savingTechAutoAssign
                        ? null
                        : (v) => _setTechAutoAssignSelf(v),
                  ),
                  onTap: _savingTechAutoAssign
                      ? null
                      : () => _setTechAutoAssignSelf(!_techAutoAssignSelf),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
