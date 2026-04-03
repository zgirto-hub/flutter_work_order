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
import '../services/activity_log_service.dart';
import 'settings/notification_settings_section.dart';
import 'settings/activity_log_screen.dart';
import 'admin/user_management_screen.dart';
import 'admin/department_routes_screen.dart';
import 'admin/departments_screen.dart';
import '../widgets/nav_bar_customization_sheet.dart';
import '../widgets/bottom_sheet_widgets.dart';

class SettingsPage extends StatefulWidget {
  final ThemeController themeController;
  final String userRole;
  final List<String>? allowedScreens;
  const SettingsPage(
      {super.key,
      required this.themeController,
      this.userRole = 'admin',
      this.allowedScreens});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const String _currentReleaseId =
      String.fromEnvironment('RELEASE_ID', defaultValue: '');
  String version = '';
  String buildNumber = '';
  String updateMessage = '';
  bool checkingUpdate = false;
  bool updateAvailable = false;
  static const _fontScales = [0.85, 1.0, 1.15, 1.3];
  static const _fontLabels = ['Small', 'Default', 'Large', 'X-Large'];

  @override
  void initState() {
    super.initState();
    _loadVersion();
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
      if (kIsWeb) {
        final releaseRes = await http.get(
          Uri.parse(
            '${Uri.base.origin}/release.json?ts=${DateTime.now().millisecondsSinceEpoch}',
          ),
        );
        if (releaseRes.statusCode == 200) {
          final data = jsonDecode(releaseRes.body) as Map<String, dynamic>;
          final latest = (data['version'] as String?)?.trim() ?? '';
          final latestReleaseId = (data['release_id'] as String?)?.trim() ?? '';
          final hasUpdate =
              latestReleaseId.isNotEmpty && _currentReleaseId.isNotEmpty
                  ? latestReleaseId != _currentReleaseId
                  : latest.isNotEmpty && latest != version.split('+')[0];
          setState(() {
            updateAvailable = hasUpdate;
            updateMessage = hasUpdate
                ? 'Update available: ${latest.isNotEmpty ? latest : 'new release'}'
                : 'You are on the latest version';
          });
          setState(() => checkingUpdate = false);
          return;
        }
      }

      final res = await http.get(Uri.parse('${AppConfig.baseUrl}/version'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final latest = (data['version'] as String?)?.trim() ?? '';
        final latestReleaseId = (data['release_id'] as String?)?.trim() ?? '';
        final hasUpdate =
            latestReleaseId.isNotEmpty && _currentReleaseId.isNotEmpty
                ? latestReleaseId != _currentReleaseId
                : latest != version.split('+')[0];
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

  Future<void> _signOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.bgSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text('Sign out',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        content: Text('Are you sure you want to sign out?',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
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
                        width: 34,
                        height: 34,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: AppColors.bgSurface2,
                          borderRadius: BorderRadius.circular(9),
                          border:
                              Border.all(color: AppColors.border2, width: 0.5),
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
                    InitialsAvatar(name: nameInitials, size: 42, large: true),
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
                                  fontSize: 11, color: AppColors.textTertiary)),
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
                    _FontSizeRow(
                      currentScale: currentScale,
                      scales: _fontScales,
                      labels: _fontLabels,
                      onChanged: (scale) =>
                          widget.themeController.setFontScale(scale),
                    ),
                    Divider(height: 0, thickness: 0.5, color: AppColors.border),
                    _FontTypeRow(
                      currentFamily: widget.themeController.fontFamily,
                      onChanged: (family) =>
                          widget.themeController.setFontFamily(family),
                    ),
                    Divider(height: 0, thickness: 0.5, color: AppColors.border),
                    _NavBarRow(
                      pinnedCount:
                          widget.themeController.pinnedNavScreens.length,
                      onTap: () => showAppBottomSheet(
                        context: context,
                        child: NavBarCustomizationSheet(
                          themeController: widget.themeController,
                          userRole: widget.userRole,
                          allowedScreens: widget.allowedScreens,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 12),
              NotificationSettingsSection(userRole: widget.userRole),
              SizedBox(height: 12),
              if (widget.userRole == 'admin') ...[
                SectionLabel(text: 'Administration'),
                SurfaceCard(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Column(
                    children: [
                      SettingsRow(
                        icon: Icons.history_rounded,
                        label: 'Activity log',
                        subtitle: 'View all user actions',
                        showDivider: true,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ActivityLogScreen(),
                          ),
                        ),
                      ),
                      SettingsRow(
                        icon: Icons.people_outlined,
                        label: 'User Management',
                        subtitle: 'Manage users, roles, and departments',
                        showDivider: true,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const UserManagementScreen(),
                          ),
                        ),
                      ),
                      SettingsRow(
                        icon: Icons.business_outlined,
                        label: 'Departments',
                        subtitle: 'Manage departments',
                        showDivider: true,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const DepartmentsScreen(),
                          ),
                        ),
                      ),
                      SettingsRow(
                        icon: Icons.alt_route_outlined,
                        label: 'Department Routing',
                        subtitle: 'Configure WO routing between departments',
                        showDivider: false,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const DepartmentRoutesScreen(),
                          ),
                        ),
                      ),
                    ],
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
                  subtitle: version.isNotEmpty
                      ? 'v$version (Build $buildNumber)'
                      : null,
                  showDivider: false,
                  onTap: checkingUpdate ? null : _checkUpdates,
                  trailing: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: checkingUpdate
                        ? SizedBox(
                            key: ValueKey('spinner'),
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: AppColors.textTertiary))
                        : Icon(Icons.chevron_right_rounded,
                            key: ValueKey('chevron'),
                            size: 16,
                            color: AppColors.textTertiary),
                  ),
                ),
              ),
              AnimatedOpacity(
                opacity: updateMessage.isNotEmpty ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 250),
                child: updateMessage.isNotEmpty
                    ? Padding(
                        padding: const EdgeInsets.only(top: 8, left: 4),
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
                      )
                    : SizedBox.shrink(),
              ),
              SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _signOut,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.dangerText,
                    side: BorderSide(color: AppColors.dangerBorder, width: 0.5),
                    backgroundColor: AppColors.dangerBg,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text('Sign out',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
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
                              fontSize: 10, color: AppColors.textTertiary)),
                    SizedBox(height: 2),
                    Text('Developed by Salah · 2026',
                        style: TextStyle(
                            fontSize: 10, color: AppColors.textTertiary)),
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
    (ThemeMode.light, Icons.wb_sunny_rounded, 'Light'),
    (ThemeMode.system, Icons.brightness_auto_rounded, 'System'),
    (ThemeMode.dark, Icons.nightlight_round, 'Dark'),
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color:
                          isSelected ? AppColors.bgSurface : Colors.transparent,
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
                            fontWeight:
                                isSelected ? FontWeight.w600 : FontWeight.w400,
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

  const _FontTypeRow({required this.currentFamily, required this.onChanged});

  static TextStyle _previewStyle(String family) {
    return switch (family) {
      'Roboto' => GoogleFonts.roboto(fontSize: 13, fontWeight: FontWeight.w500),
      'Poppins' =>
        GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500),
      'Lato' => GoogleFonts.lato(fontSize: 13, fontWeight: FontWeight.w500),
      'Nunito' => GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w500),
      _ => GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500),
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
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.accent : AppColors.bgSurface2,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                      color: isSelected ? AppColors.accent : AppColors.border2,
                      width: 0.5,
                    ),
                  ),
                  child: Text(
                    family,
                    style: _previewStyle(family).copyWith(
                      color:
                          isSelected ? Colors.white : AppColors.textSecondary,
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
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: AppColors.accentBg,
                    borderRadius: BorderRadius.circular(10)),
                child: Text(
                  labels[scales
                      .indexWhere((s) => (s - currentScale).abs() < 0.01)
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
              final isSelected = (currentScale - scales[i]).abs() < 0.01;
              return Expanded(
                child: GestureDetector(
                  onTap: () => onChanged(scales[i]),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin:
                        EdgeInsets.only(right: i < scales.length - 1 ? 6 : 0),
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      color:
                          isSelected ? AppColors.accent : AppColors.bgSurface2,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(
                        color:
                            isSelected ? AppColors.accent : AppColors.border2,
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

// ─── Nav Bar Row ─────────────────────────────────────────────────────────────

class _NavBarRow extends StatelessWidget {
  final int pinnedCount;
  final VoidCallback onTap;

  const _NavBarRow({required this.pinnedCount, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.bgSurface2,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.tab_rounded,
                  size: 15, color: AppColors.textSecondary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Navigation bar',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.accentBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                pinnedCount > 0 ? '$pinnedCount pinned' : 'Default',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: AppColors.accent,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded,
                size: 16, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}
