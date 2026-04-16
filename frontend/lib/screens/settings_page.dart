import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:async';
import '../services/pwa_update_stub.dart'
    if (dart.library.js_interop) '../services/pwa_update_web.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import '../widgets/claude_widgets.dart';
import '../widgets/change_password_dialog.dart';
import '../services/activity_log_service.dart';
import 'settings/notification_settings_section.dart';
import 'settings/activity_log_screen.dart';
import 'settings/signature_management_screen.dart';
import 'admin/user_management_screen.dart';
import 'admin/department_routes_screen.dart';
import 'admin/departments_screen.dart';
import 'admin/infrastructure_screen.dart';
import 'admin/settings_screen.dart';
import '../widgets/nav_bar_customization_sheet.dart';
import '../widgets/bottom_sheet_widgets.dart';
import '../services/manual_assistant_service.dart';
import '../services/ai_provider_service.dart';
import '../models/ai_provider.dart';

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
  String version = '';
  String buildNumber = '';
  String updateMessage = '';
  bool checkingUpdate = false;
  bool updateAvailable = false;
  static const _fontScales = [1.0, 1.15, 1.3, 1.45];
  static const _fontLabels = ['Small', 'Default', 'Large', 'X-Large'];

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    setState(() {
      version = info.version;
      buildNumber = info.buildNumber;
    });
  }

  String _formatUpdateMessage(UpdateInfo info) {
    if (info.version != null && info.build != null) {
      return 'v${info.version} (Build ${info.build}) is available';
    } else if (info.version != null) {
      return 'v${info.version} is available';
    }
    return 'A new version is available';
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

    if (kIsWeb) {
      // Register callback for background detection
      registerUpdateCallback(() {
        if (mounted && !updateAvailable) {
          checkForUpdate().then((info) {
            if (mounted) {
              setState(() {
                updateAvailable = true;
                updateMessage = _formatUpdateMessage(info);
                checkingUpdate = false;
              });
            }
          });
        }
      });

      // Perform an immediate check
      final info = await checkForUpdate();
      if (mounted) {
        setState(() {
          switch (info.status) {
            case UpdateStatus.available:
              updateAvailable = true;
              updateMessage = _formatUpdateMessage(info);
            case UpdateStatus.upToDate:
              updateMessage = 'You are on the latest version';
            case UpdateStatus.error:
              updateMessage = 'You are on the latest version';
          }
          checkingUpdate = false;
        });
      }
      return;
    }

    setState(() {
      updateMessage = 'You are on the latest version';
      checkingUpdate = false;
    });
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
              if (widget.userRole == 'technician' ||
                  widget.userRole == 'admin') ...[
                SizedBox(height: 12),
                SectionLabel(text: 'My Signature'),
                SurfaceCard(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: SettingsRow(
                    icon: Icons.draw_outlined,
                    label: 'Manage signature',
                    subtitle: 'Draw, upload, or remove your signature',
                    showDivider: false,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const SignatureManagementScreen(),
                      ),
                    ),
                  ),
                ),
              ],
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
                SectionLabel(text: 'AI Model'),
                _AiModelSection(),
                SizedBox(height: 12),
                SectionLabel(text: 'AI Assistant'),
                _AiProviderSection(),
                SizedBox(height: 12),
                SmartPreprocessingSection(),
                SizedBox(height: 12),
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
                        icon: Icons.hub_outlined,
                        label: 'Infrastructure',
                        subtitle: 'Manage systems, sites, and linked assets',
                        showDivider: true,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const InfrastructureScreen(),
                          ),
                        ),
                      ),
                      SettingsRow(
                        icon: Icons.alt_route_outlined,
                        label: 'Department Routing',
                        subtitle: 'Configure WO routing between departments',
                        showDivider: true,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const DepartmentRoutesScreen(),
                          ),
                        ),
                      ),
                      SettingsRow(
                        icon: Icons.settings_outlined,
                        label: 'Settings',
                        subtitle: 'System settings',
                        showDivider: false,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SettingsScreen(),
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
                                onTap: () {
                                  if (kIsWeb) applyUpdate();
                                },
                                child: Text('Tap to update',
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

// ─── AI Model Section ────────────────────────────────────────────────────────

class _AiModelSection extends StatefulWidget {
  @override
  State<_AiModelSection> createState() => _AiModelSectionState();
}

class _AiModelSectionState extends State<_AiModelSection> {
  final _service = ManualAssistantService();
  List<Map<String, dynamic>> _models = [];
  String? _currentModel;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final models = await _service.listModels();
    final current = await _service.getDefaultModel();
    if (mounted) {
      setState(() {
        _models = models;
        _currentModel = current.isNotEmpty ? current : null;
        _loading = false;
      });
    }
  }

  Future<void> _setModel(String model) async {
    setState(() => _saving = true);
    final saved = await _service.setDefaultModel(model);
    if (mounted) {
      setState(() {
        _currentModel = saved;
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Default AI model set to $saved'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return SurfaceCard(
        padding: const EdgeInsets.all(14),
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
                strokeWidth: 1.5, color: AppColors.textTertiary),
          ),
        ),
      );
    }

    return SurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.bgSurface2,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.smart_toy_outlined,
                    size: 15, color: AppColors.textSecondary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Default model',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary),
                ),
              ),
              if (_saving)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 1.5, color: AppColors.textTertiary),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (_models.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('No models available',
                  style:
                      TextStyle(fontSize: 12, color: AppColors.textTertiary)),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _models.map((m) {
                final name = m['name'] as String;
                final sizeGb = m['size_gb'];
                final isSelected = name == _currentModel;
                return GestureDetector(
                  onTap: _saving ? null : () => _setModel(name),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                          name,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight:
                                isSelected ? FontWeight.w600 : FontWeight.w500,
                            color: isSelected
                                ? Colors.white
                                : AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${sizeGb}G',
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
                );
              }).toList(),
            ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

// ─── AI Provider Section ────────────────────────────────────────────────────────

class _AiProviderSection extends StatefulWidget {
  @override
  State<_AiProviderSection> createState() => _AiProviderSectionState();
}

class _AiProviderSectionState extends State<_AiProviderSection> {
  final _service = AiProviderService();
  List<AiProvider> _providers = [];
  String _activeProvider = 'local';
  bool _loading = true;
  bool _saving = false;
  bool _healthLoading = false;
  bool _isHealthy = true;
  String? _healthReason;
  List<Map<String, String>> _geminiModels = [];
  String _activeGeminiModel = 'gemini-2.0-flash';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final resp = await _service.listProviders();
      if (mounted) {
        setState(() {
          _providers = resp.providers;
          _activeProvider = resp.active;
          _loading = false;
        });
        _checkHealth();
        if (_activeProvider == 'gemini') _loadGeminiModels();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadGeminiModels() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user?.email == null) return;
    try {
      final resp = await _service.getGeminiModels(user!.email!);
      if (mounted) {
        setState(() {
          _geminiModels = resp.models;
          _activeGeminiModel = resp.activeModel;
        });
      }
    } catch (_) {}
  }

  Future<void> _setGeminiModel(String modelId) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user?.email == null) return;
    setState(() => _saving = true);
    try {
      await _service.setGeminiModel(modelId, user!.email!);
      if (mounted) {
        setState(() {
          _activeGeminiModel = modelId;
          _saving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gemini model set to $modelId'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _checkHealth() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user?.email == null) return;
    setState(() => _healthLoading = true);
    try {
      final health = await _service.getHealth(user!.email!);
      if (mounted) {
        setState(() {
          _isHealthy = health.healthy;
          _healthReason = health.reason;
          _healthLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _healthLoading = false);
      }
    }
  }

  Future<void> _setProvider(String key) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user?.email == null) return;
    setState(() => _saving = true);
    try {
      await _service.setActiveProvider(key, user!.email!);
      if (mounted) {
        setState(() {
          _activeProvider = key;
          _saving = false;
        });
        if (key == 'gemini') _loadGeminiModels();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('AI provider set to $key'),
            duration: const Duration(seconds: 2),
          ),
        );
        _checkHealth();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to set provider'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return SurfaceCard(
        padding: const EdgeInsets.all(14),
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
                strokeWidth: 1.5, color: AppColors.textTertiary),
          ),
        ),
      );
    }

    return SurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.bgSurface2,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.smart_toy_outlined,
                    size: 18, color: AppColors.textSecondary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI Assistant Provider',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _healthLoading
                                ? AppColors.textTertiary
                                : (_isHealthy
                                    ? const Color(0xFF22C55E)
                                    : const Color(0xFFDC2626)),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _healthLoading
                              ? 'Checking...'
                              : (_isHealthy ? 'Healthy' : 'Unhealthy'),
                          style: TextStyle(
                            fontSize: 11,
                            color: _isHealthy
                                ? const Color(0xFF22C55E)
                                : const Color(0xFFDC2626),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (_saving)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 1.5, color: AppColors.textTertiary),
                ),
            ],
          ),
          if (_providers.length > 1) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _providers.map((p) {
                final isSelected = p.key == _activeProvider;
                return GestureDetector(
                  onTap: () => _setProvider(p.key),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color:
                          isSelected ? AppColors.accent : AppColors.bgSurface2,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      p.displayName,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color:
                            isSelected ? Colors.white : AppColors.textSecondary,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
          if (_activeProvider == 'gemini' && _geminiModels.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.bgSurface2,
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _activeGeminiModel,
                  isExpanded: true,
                  icon: Icon(Icons.expand_more, size: 18, color: AppColors.textSecondary),
                  style: TextStyle(fontSize: 12, color: AppColors.textPrimary),
                  dropdownColor: AppColors.bgSurface,
                  items: _geminiModels.map((m) {
                    return DropdownMenuItem<String>(
                      value: m['id'],
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              m['name'] ?? '',
                              style: TextStyle(fontSize: 12, color: AppColors.textPrimary),
                            ),
                          ),
                          Text(
                            m['free_quota'] ?? '',
                            style: TextStyle(fontSize: 10, color: AppColors.textTertiary),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (v) {
                    if (v != null && v != _activeGeminiModel) _setGeminiModel(v);
                  },
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class SmartPreprocessingSection extends StatelessWidget {
  const SmartPreprocessingSection({super.key});

  @override
  Widget build(BuildContext context) {
    return _SmartPreprocessingWidget();
  }
}

class _SmartPreprocessingWidget extends StatefulWidget {
  @override
  State<_SmartPreprocessingWidget> createState() =>
      _SmartPreprocessingWidgetState();
}

class _SmartPreprocessingWidgetState extends State<_SmartPreprocessingWidget> {
  final _service = AiProviderService();
  bool _loading = true;
  bool _enabled = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user?.email == null) return;
    try {
      final enabled = await _service.getSmartPreprocessing(user!.email!);
      if (mounted) {
        setState(() {
          _enabled = enabled;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _toggle(bool value) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user?.email == null) return;
    setState(() => _saving = true);
    try {
      await _service.setSmartPreprocessing(value, user!.email!);
      if (mounted) {
        setState(() {
          _enabled = value;
          _saving = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return SurfaceCard(
        padding: const EdgeInsets.all(14),
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
                strokeWidth: 1.5, color: AppColors.textTertiary),
          ),
        ),
      );
    }

    return SurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.bgSurface2,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.auto_fix_high,
                size: 18, color: AppColors.textSecondary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Smart Document Preprocessing',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'When enabled, uploaded documents are enhanced with AI to improve search quality',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (_saving)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 1.5, color: AppColors.textTertiary),
            )
          else
            Switch(
              value: _enabled,
              onChanged: _toggle,
              activeColor: AppColors.accent,
            ),
        ],
      ),
    );
  }
}
