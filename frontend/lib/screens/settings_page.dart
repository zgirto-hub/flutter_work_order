import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../services/pwa_update_stub.dart'
    if (dart.library.js_interop) '../services/pwa_update_web.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import '../widgets/claude_widgets.dart';
import '../widgets/change_password_dialog.dart';
import '../config.dart';
import '../services/onesignal_service.dart';
import '../services/activity_log_service.dart';
import 'settings/activity_log_screen.dart';


class SettingsPage extends StatefulWidget {
  final ThemeController themeController;
  final String userRole;
  const SettingsPage(
      {super.key,
      required this.themeController,
      this.userRole = 'admin'});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String version = '';
  String buildNumber = '';
  String updateMessage = '';
  bool checkingUpdate = false;
  bool updateAvailable = false;
  bool _notificationsEnabled = false;
  Color _selectedColor = AppColors.textPrimary;

  static const _colorOptions = [
    Color(0xFF1A1915),
    Color(0xFFCC785C),
    Color(0xFF15803D),
    Color(0xFF1D4ED8),
    Color(0xFF7C3AED),
  ];
  static const _fontScales = [0.85, 1.0, 1.15, 1.3];
  static const _fontLabels = ['Small', 'Default', 'Large', 'X-Large'];

  @override
  void initState() {
    super.initState();
    _loadVersion();
    _selectedColor = widget.themeController.color;
    _notificationsEnabled = OneSignalService.isGranted();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    setState(() {
      version = info.version;
      buildNumber = info.buildNumber;
    });
  }

  Future<void> _checkUpdates() async {
    setState(() {
      checkingUpdate = true;
      updateMessage = '';
      updateAvailable = false;
    });
    final email = Supabase.instance.client.auth.currentUser?.email;
    if (email != null) {
      ActivityLogService().logUpdateCheck(email);
    }
    try {
      final res =
          await http.get(Uri.parse('${AppConfig.baseUrl}/version'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final latest = data['version'] as String;
        final hasUpdate = latest != version.split('+')[0];
        setState(() {
          updateAvailable = hasUpdate;
          updateMessage = hasUpdate
              ? 'Update available: $latest'
              : 'You are on the latest version';
        });
      } else {
        setState(() => updateMessage = 'Could not check for updates');
      }
    } catch (_) {
      setState(() => updateMessage = 'Update check failed');
    }
    setState(() => checkingUpdate = false);
  }

  void _applyUpdate() {
    if (kIsWeb) applyPWAUpdate();
  }

  Future<void> _showCreateAccountDialog(BuildContext context) async {
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    String selectedRole = 'requester';
    bool loading = false;

    await showDialog(
      context: context,
      barrierDismissible: !loading,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: AppColors.bgSurface,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
          title: Text('Create Account',
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Email',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textTertiary)),
              SizedBox(height: 4),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.bgSurface2,
                  borderRadius: BorderRadius.circular(10),
                  border:
                      Border.all(color: AppColors.border, width: 0.5),
                ),
                child: TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  style: TextStyle(
                      fontSize: 13, color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'user@company.com',
                    hintStyle: TextStyle(
                        fontSize: 13, color: AppColors.textTertiary),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                ),
              ),
              SizedBox(height: 12),
              Text('Password',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textTertiary)),
              SizedBox(height: 4),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.bgSurface2,
                  borderRadius: BorderRadius.circular(10),
                  border:
                      Border.all(color: AppColors.border, width: 0.5),
                ),
                child: TextField(
                  controller: passCtrl,
                  obscureText: true,
                  style: TextStyle(
                      fontSize: 13, color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    hintText: '••••••••',
                    hintStyle: TextStyle(
                        fontSize: 13, color: AppColors.textTertiary),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                ),
              ),
              SizedBox(height: 14),
              Text('Role',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textTertiary)),
              SizedBox(height: 6),
              Row(
                children: ['requester', 'tech'].map((role) {
                  final isSel = selectedRole == role;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () =>
                          setDlg(() => selectedRole = role),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        margin: EdgeInsets.only(
                            right: role == 'requester' ? 6 : 0),
                        padding:
                            const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: isSel
                              ? AppColors.textPrimary
                              : AppColors.bgSurface2,
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(
                            color: isSel
                                ? AppColors.textPrimary
                                : AppColors.border2,
                            width: 0.5,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            role == 'requester' ? 'Requester' : 'Tech',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: isSel
                                  ? Colors.white
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: loading ? null : () => Navigator.pop(ctx),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: loading
                  ? null
                  : () async {
                      final email = emailCtrl.text.trim();
                      final password = passCtrl.text;
                      if (email.isEmpty || password.isEmpty) return;
                      setDlg(() => loading = true);
                      try {
                        final res = await http.post(
                          Uri.parse(
                              '${AppConfig.baseUrl}/admin/create-user'),
                          headers: {
                            'Content-Type': 'application/json'
                          },
                          body: jsonEncode({
                            'email': email,
                            'password': password,
                            'user_type': selectedRole,
                          }),
                        );
                        if (!ctx.mounted) return;
                        if (res.statusCode == 200) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context)
                              .showSnackBar(SnackBar(
                            content:
                                Text('Account created for $email'),
                            backgroundColor: AppColors.closedText,
                            behavior: SnackBarBehavior.floating,
                          ));
                        } else {
                          final body = jsonDecode(res.body);
                          setDlg(() => loading = false);
                          ScaffoldMessenger.of(context)
                              .showSnackBar(SnackBar(
                            content: Text(body['detail'] ??
                                'Failed to create account'),
                            backgroundColor: AppColors.dangerText,
                            behavior: SnackBarBehavior.floating,
                          ));
                        }
                      } catch (e) {
                        setDlg(() => loading = false);
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(
                          content: Text('Error: $e'),
                          backgroundColor: AppColors.dangerText,
                          behavior: SnackBarBehavior.floating,
                        ));
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: loading
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 1.5, color: Colors.white),
                    )
                  : Text('Create',
                      style: TextStyle(fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _signOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.bgSurface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14)),
        title: Text('Sign out',
            style:
                TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        content: Text('Are you sure you want to sign out?',
            style: TextStyle(
                fontSize: 13, color: AppColors.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('Sign out')),
        ],
      ),
    );
    if (confirm == true) {
      final email = Supabase.instance.client.auth.currentUser?.email;
      if (email != null) {
        try {
          await ActivityLogService().logSignOut(email);
        } catch (_) {}
      }
      await Supabase.instance.client.auth.signOut();
      if (mounted) {
        Navigator.of(context, rootNavigator: true)
            .popUntil((route) => route.isFirst);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final email = user?.email ?? 'Unknown';
    final nameInitials = email.split('@').first;
    final currentScale = widget.themeController.fontScale;

    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (Navigator.canPop(context))
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 34, height: 34,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: AppColors.bgSurface2,
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(
                              color: AppColors.border2, width: 0.5),
                        ),
                        child: Icon(Icons.arrow_back_rounded,
                            size: 16, color: AppColors.textSecondary),
                      ),
                    ),
                  Text('Settings',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                          letterSpacing: -0.3)),
                ],
              ),
              SizedBox(height: 16),

              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                    color: AppColors.bgSurface2,
                    borderRadius: BorderRadius.circular(14)),
                child: Row(
                  children: [
                    InitialsAvatar(
                        name: nameInitials, size: 42, large: true),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(nameInitials,
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary)),
                          SizedBox(height: 2),
                          Text(email,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textTertiary)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: 12),

              SectionLabel(text: 'Account'),
              SurfaceCard(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: SettingsRow(
                  icon: Icons.lock_outline_rounded,
                  label: 'Change password',
                  showDivider: false,
                  onTap: () => showDialog(
                      context: context,
                      builder: (_) => const ChangePasswordDialog()),
                ),
              ),

              SizedBox(height: 12),

              SectionLabel(text: 'Appearance'),
              SurfaceCard(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
                child: Column(
                  children: [
                    _DarkModeRow(
                      mode: widget.themeController.mode,
                      onChanged: widget.themeController.setThemeMode,
                    ),
                    Divider(height: 0, thickness: 0.5, color: AppColors.border),
                    SettingsRow(
                      icon: Icons.palette_outlined,
                      label: 'Theme color',
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: _colorOptions.map((c) {
                          final isSel = _selectedColor == c;
                          return GestureDetector(
                            onTap: () {
                              setState(() => _selectedColor = c);
                              widget.themeController.changeColor(c);
                            },
                            child: AnimatedContainer(
                              duration:
                                  const Duration(milliseconds: 150),
                              width: isSel ? 22 : 18,
                              height: isSel ? 22 : 18,
                              margin: const EdgeInsets.only(left: 6),
                              decoration: BoxDecoration(
                                color: c,
                                shape: BoxShape.circle,
                                border: isSel
                                    ? Border.all(
                                        color: AppColors.textPrimary,
                                        width: 2)
                                    : Border.all(
                                        color: AppColors.border2,
                                        width: 0.5),
                              ),
                              child: isSel
                                  ? Icon(Icons.check_rounded,
                                      color: Colors.white, size: 11)
                                  : null,
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    Divider(
                        height: 0,
                        thickness: 0.5,
                        color: AppColors.border),
                    _FontSizeRow(
                      currentScale: currentScale,
                      scales: _fontScales,
                      labels: _fontLabels,
                      onChanged: (scale) =>
                          widget.themeController.setFontScale(scale),
                    ),
                    Divider(
                        height: 0,
                        thickness: 0.5,
                        color: AppColors.border),
                    _FontTypeRow(
                      currentFamily: widget.themeController.fontFamily,
                      onChanged: (family) =>
                          widget.themeController.setFontFamily(family),
                    ),
                  ],
                ),
              ),

              SizedBox(height: 12),

              if (widget.userRole != 'requester') ...[
                SectionLabel(text: 'Notifications'),
                SurfaceCard(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: SettingsRow(
                    icon: _notificationsEnabled
                        ? Icons.notifications_active_outlined
                        : Icons.notifications_outlined,
                    label: _notificationsEnabled
                        ? 'Disable push notifications'
                        : 'Enable push notifications',
                    subtitle: 'Get notified when new requests arrive',
                    showDivider: false,
                    onTap: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      if (_notificationsEnabled) {
                        try {
                          await OneSignalService.unsubscribe();
                        } catch (_) {}
                        setState(() => _notificationsEnabled = false);
                        messenger.showSnackBar(SnackBar(
                          content:
                              Text('Notifications disabled'),
                          backgroundColor: AppColors.dangerText,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ));
                      } else {
                        bool granted = false;
                        try {
                          granted =
                              await OneSignalService.requestPermission();
                        } catch (_) {}
                        setState(() => _notificationsEnabled = granted);
                        messenger.showSnackBar(SnackBar(
                          content: Text(granted
                              ? 'Notifications enabled!'
                              : 'Notifications blocked — check browser settings'),
                          backgroundColor: granted
                              ? AppColors.closedText
                              : AppColors.dangerText,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ));
                      }
                    },
                  ),
                ),
                SizedBox(height: 12),
              ],

              if (widget.userRole == 'admin') ...[
                SectionLabel(text: 'User Management'),
                SurfaceCard(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: SettingsRow(
                    icon: Icons.person_add_outlined,
                    label: 'Create account',
                    subtitle: 'Add a tech or requester user',
                    showDivider: false,
                    onTap: () => _showCreateAccountDialog(context),
                  ),
                ),
                SizedBox(height: 12),
                SectionLabel(text: 'System'),
                SurfaceCard(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: SettingsRow(
                    icon: Icons.history_rounded,
                    label: 'Activity log',
                    subtitle: 'View all user actions',
                    showDivider: false,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ActivityLogScreen(),
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 12),
              ],

              SectionLabel(text: 'Application'),
              SurfaceCard(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: SettingsRow(
                  icon: Icons.system_update_outlined,
                  label: 'Check for updates',
                  subtitle: version.isNotEmpty ? 'v$version' : null,
                  showDivider: false,
                  onTap: checkingUpdate ? null : _checkUpdates,
                  trailing: checkingUpdate
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: AppColors.textTertiary))
                      : Icon(Icons.chevron_right_rounded,
                          size: 16, color: AppColors.textTertiary),
                ),
              ),

              if (updateMessage.isNotEmpty) ...[
                SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    children: [
                      Text(updateMessage,
                          style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textTertiary)),
                      if (updateAvailable) ...[
                        SizedBox(width: 10),
                        GestureDetector(
                          onTap: _applyUpdate,
                          child: Text('Update now',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.accent,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ],
                  ),
                ),
              ],

              SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _signOut,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.dangerText,
                    side: BorderSide(
                        color: AppColors.dangerBorder, width: 0.5),
                    backgroundColor: AppColors.dangerBg,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text('Sign out',
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w500)),
                ),
              ),

              SizedBox(height: 24),

              Center(
                child: Column(
                  children: [
                    Text('Work Order',
                        style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textTertiary,
                            fontWeight: FontWeight.w500)),
                    SizedBox(height: 3),
                    if (version.isNotEmpty)
                      Text('Version $version · Build $buildNumber',
                          style: TextStyle(
                              fontSize: 10,
                              color: AppColors.textTertiary)),
                    SizedBox(height: 2),
                    Text('Developed by Salah · 2026',
                        style: TextStyle(
                            fontSize: 10,
                            color: AppColors.textTertiary)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Dark Mode Row ────────────────────────────────────────────────────────────

class _DarkModeRow extends StatelessWidget {
  final ThemeMode mode;
  final ValueChanged<ThemeMode> onChanged;

  const _DarkModeRow({required this.mode, required this.onChanged});

  static const _options = [
    (ThemeMode.light,  Icons.wb_sunny_rounded,       'Light'),
    (ThemeMode.system, Icons.brightness_auto_rounded, 'System'),
    (ThemeMode.dark,   Icons.nightlight_round,        'Dark'),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
                color: AppColors.bgSurface2,
                borderRadius: BorderRadius.circular(8)),
            child: Icon(
              mode == ThemeMode.dark
                  ? Icons.nightlight_round
                  : mode == ThemeMode.system
                      ? Icons.brightness_auto_rounded
                      : Icons.wb_sunny_rounded,
              size: 15,
              color: AppColors.textSecondary,
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text('Appearance',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary)),
          ),
          // Segmented control — Claude.ai style
          Container(
            height: 32,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: AppColors.bgSurface2,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border, width: 0.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: _options.map((opt) {
                final (optMode, icon, label) = opt;
                final isSelected = mode == optMode;
                return GestureDetector(
                  onTap: () => onChanged(optMode),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.bgSurface : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.08),
                                blurRadius: 6,
                                offset: const Offset(0, 1),
                              )
                            ]
                          : null,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          icon,
                          size: 13,
                          color: isSelected
                              ? AppColors.textPrimary
                              : AppColors.textTertiary,
                        ),
                        SizedBox(width: 5),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: isSelected
                                ? AppColors.textPrimary
                                : AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Font Type Row ────────────────────────────────────────────────────────────

class _FontTypeRow extends StatelessWidget {
  final String currentFamily;
  final ValueChanged<String> onChanged;

  const _FontTypeRow(
      {required this.currentFamily, required this.onChanged});

  static TextStyle _previewStyle(String family) {
    return switch (family) {
      'Roboto' =>
        GoogleFonts.roboto(fontSize: 13, fontWeight: FontWeight.w500),
      'Poppins' =>
        GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500),
      'Lato' =>
        GoogleFonts.lato(fontSize: 13, fontWeight: FontWeight.w500),
      'Nunito' =>
        GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w500),
      _ =>
        GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                    color: AppColors.bgSurface2,
                    borderRadius: BorderRadius.circular(8)),
                child: Icon(Icons.font_download_outlined,
                    size: 15, color: AppColors.textSecondary),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text('Font type',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: AppColors.accentBg,
                    borderRadius: BorderRadius.circular(10)),
                child: Text(currentFamily,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: AppColors.accent)),
              ),
            ],
          ),
          SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: kAvailableFonts.map((family) {
              final isSelected = currentFamily == family;
              return GestureDetector(
                onTap: () => onChanged(family),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.accent
                        : AppColors.bgSurface2,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                      color: isSelected
                          ? AppColors.accent
                          : AppColors.border2,
                      width: 0.5,
                    ),
                  ),
                  child: Text(
                    family,
                    style: _previewStyle(family).copyWith(
                      color: isSelected
                          ? Colors.white
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ─── Font Size Row ────────────────────────────────────────────────────────────

class _FontSizeRow extends StatelessWidget {
  final double currentScale;
  final List<double> scales;
  final List<String> labels;
  final ValueChanged<double> onChanged;

  const _FontSizeRow({
    required this.currentScale,
    required this.scales,
    required this.labels,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                    color: AppColors.bgSurface2,
                    borderRadius: BorderRadius.circular(8)),
                child: Icon(Icons.text_fields_rounded,
                    size: 15, color: AppColors.textSecondary),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text('Text size',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: AppColors.accentBg,
                    borderRadius: BorderRadius.circular(10)),
                child: Text(
                  labels[scales
                      .indexWhere(
                          (s) => (s - currentScale).abs() < 0.01)
                      .clamp(0, labels.length - 1)],
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: AppColors.accent),
                ),
              ),
            ],
          ),
          SizedBox(height: 10),
          Row(
            children: List.generate(scales.length, (i) {
              final isSelected =
                  (currentScale - scales[i]).abs() < 0.01;
              return Expanded(
                child: GestureDetector(
                  onTap: () => onChanged(scales[i]),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: EdgeInsets.only(
                        right: i < scales.length - 1 ? 6 : 0),
                    padding:
                        const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.accent
                          : AppColors.bgSurface2,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(
                        color: isSelected
                            ? AppColors.accent
                            : AppColors.border2,
                        width: 0.5,
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          'Aa',
                          style: TextStyle(
                            fontSize: 10 + (i * 2.0),
                            fontWeight: FontWeight.w500,
                            color: isSelected
                                ? Colors.white
                                : AppColors.textSecondary,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          labels[i],
                          style: TextStyle(
                            fontSize: 9,
                            color: isSelected
                                ? Colors.white.withValues(alpha: 0.7)
                                : AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}
