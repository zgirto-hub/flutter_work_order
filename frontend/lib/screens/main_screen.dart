import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import '../widgets/claude_widgets.dart';
import '../widgets/change_password_dialog.dart';
import '../screens/Work_Orders/work_order_home.dart';
import '../screens/Documents/documents_screen.dart';
import '../screens/reports/workorder_report_screen.dart';  // ← fixed import
import '../config.dart';

class MainScreen extends StatefulWidget {
  final ThemeController themeController;
  const MainScreen({super.key, required this.themeController});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      const WorkOrderHome(),
      const DocumentsScreen(),
      const WorkOrderReportScreen(),
      SettingsPage(themeController: widget.themeController),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColors.bgSurface,
          border: Border(top: BorderSide(color: AppColors.border, width: 0.5)),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          backgroundColor: AppColors.bgSurface,
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.transparent,
          height: 60,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.work_outline_rounded),
              selectedIcon: Icon(Icons.work_rounded),
              label: 'Orders',
            ),
            NavigationDestination(
              icon: Icon(Icons.description_outlined),
              selectedIcon: Icon(Icons.description_rounded),
              label: 'Documents',
            ),
            NavigationDestination(
              icon: Icon(Icons.bar_chart_outlined),
              selectedIcon: Icon(Icons.bar_chart_rounded),
              label: 'Reports',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(Icons.person_rounded),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Settings Page ────────────────────────────────────────────────────────────

class SettingsPage extends StatefulWidget {
  final ThemeController themeController;
  const SettingsPage({super.key, required this.themeController});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String version = '';
  String buildNumber = '';
  String updateMessage = '';
  bool checkingUpdate = false;
  Color _selectedColor = AppColors.textPrimary;

  final _colorOptions = const [
    Color(0xFF1A1915),
    Color(0xFFCC785C),
    Color(0xFF15803D),
    Color(0xFF1D4ED8),
    Color(0xFF7C3AED),
  ];

  @override
  void initState() {
    super.initState();
    _loadVersion();
    _selectedColor = widget.themeController.color;
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    setState(() {
      version = info.version;
      buildNumber = info.buildNumber;
    });
  }

  Future<void> _checkUpdates() async {
    setState(() { checkingUpdate = true; updateMessage = ''; });
    try {
      final res = await http.get(Uri.parse('${AppConfig.baseUrl}/version'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final latest = data['version'] as String;
        setState(() => updateMessage = latest != version.split('+')[0]
            ? 'Update available: $latest'
            : 'You are on the latest version');
      } else {
        setState(() => updateMessage = 'Could not check for updates');
      }
    } catch (_) {
      setState(() => updateMessage = 'Update check failed');
    }
    setState(() => checkingUpdate = false);
  }

  Future<void> _signOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.bgSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Sign out',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        content: const Text('Are you sure you want to sign out?',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Sign out')),
        ],
      ),
    );
    if (confirm == true) await Supabase.instance.client.auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final email = user?.email ?? 'Unknown';
    final nameInitials = email.split('@').first;

    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              const Text('Settings',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                      letterSpacing: -0.3)),

              const SizedBox(height: 16),

              // Profile card
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.bgSurface2,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    InitialsAvatar(name: nameInitials, size: 42, large: true),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(nameInitials,
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary)),
                          const SizedBox(height: 2),
                          Text(email,
                              style: const TextStyle(
                                  fontSize: 11, color: AppColors.textTertiary)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              SectionLabel(text: 'Account'),

              SurfaceCard(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Column(
                  children: [
                    SettingsRow(
                      icon: Icons.lock_outline_rounded,
                      label: 'Change password',
                      onTap: () => showDialog(
                          context: context,
                          builder: (_) => const ChangePasswordDialog()),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              SectionLabel(text: 'Appearance'),

              SurfaceCard(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
                child: SettingsRow(
                  icon: Icons.palette_outlined,
                  label: 'Theme color',
                  showDivider: false,
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
                          duration: const Duration(milliseconds: 150),
                          width: isSel ? 22 : 18,
                          height: isSel ? 22 : 18,
                          margin: const EdgeInsets.only(left: 6),
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: isSel
                                ? Border.all(
                                    color: AppColors.textPrimary, width: 2)
                                : Border.all(
                                    color: AppColors.border2, width: 0.5),
                          ),
                          child: isSel
                              ? const Icon(Icons.check_rounded,
                                  color: Colors.white, size: 11)
                              : null,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              SectionLabel(text: 'Application'),

              SurfaceCard(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Column(
                  children: [
                    SettingsRow(
                      icon: Icons.system_update_outlined,
                      label: 'Check for updates',
                      subtitle: version.isNotEmpty ? 'v$version' : null,
                      onTap: checkingUpdate ? null : _checkUpdates,
                      trailing: checkingUpdate
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                  color: AppColors.textTertiary),
                            )
                          : const Icon(Icons.chevron_right_rounded,
                              size: 16, color: AppColors.textTertiary),
                      showDivider: false,
                    ),
                  ],
                ),
              ),

              if (updateMessage.isNotEmpty) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(updateMessage,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textTertiary)),
                ),
              ],

              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _signOut,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.dangerText,
                    side: const BorderSide(
                        color: AppColors.dangerBorder, width: 0.5),
                    backgroundColor: AppColors.dangerBg,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Sign out',
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w500)),
                ),
              ),

              const SizedBox(height: 24),

              Center(
                child: Column(
                  children: [
                    const Text('Work Order',
                        style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textTertiary,
                            fontWeight: FontWeight.w500)),
                    const SizedBox(height: 3),
                    if (version.isNotEmpty)
                      Text('Version $version · Build $buildNumber',
                          style: const TextStyle(
                              fontSize: 10, color: AppColors.textTertiary)),
                    const SizedBox(height: 2),
                    const Text('Developed by Salah · 2026',
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
