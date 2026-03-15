import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:js_interop';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import 'package:google_fonts/google_fonts.dart';
import '../widgets/claude_widgets.dart';
import '../widgets/change_password_dialog.dart';
import '../screens/Work_Orders/work_order_home.dart';
import '../screens/Documents/documents_screen.dart';
import '../screens/reports/workorder_report_screen.dart';
import '../screens/Requests/requests_screen.dart';
import '../config.dart';
import '../services/request_service.dart';
import '../services/onesignal_service.dart';

@JS('applyPWAUpdate')
external void _jsApplyPWAUpdate();

@JS('setAppBadge')
external void _jsSetAppBadge(int count);

class MainScreen extends StatefulWidget {
  final ThemeController themeController;
  const MainScreen({super.key, required this.themeController});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _index = 0;
  String _userRole = 'admin';
  bool _roleLoaded = false;
  int _openRequestCount = 0;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _loadUserRole();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadUserRole() async {
    final email = Supabase.instance.client.auth.currentUser?.email;
    if (email == null) {
      if (mounted) setState(() => _roleLoaded = true);
      return;
    }
    final role = await RequestService().getUserRole(email);
    if (!mounted) return;
    setState(() {
      _userRole = role;
      _index = 0;
      _roleLoaded = true;
    });
    if (role != 'requester') {
      _refreshRequestCount();
      _startPolling();
      OneSignalService.subscribe(email, role);
    } else {
      OneSignalService.unsubscribe();
    }
  }

  Future<void> _refreshRequestCount() async {
    try {
      final res = await http.get(Uri.parse('${AppConfig.baseUrl}/requests/count-open'));
      if (!mounted) return;
      if (res.statusCode == 200) {
        final count = jsonDecode(res.body)['count'] as int? ?? 0;
        setState(() => _openRequestCount = count);
        if (kIsWeb) _jsSetAppBadge(count);
      }
    } catch (_) {}
  }

  void _startPolling() {
    _pollTimer = Timer.periodic(const Duration(seconds: 20), (_) async {
      try {
        final res = await http.get(Uri.parse('${AppConfig.baseUrl}/requests/count-open'));
        if (!mounted) return;
        if (res.statusCode == 200) {
          final newCount = jsonDecode(res.body)['count'] as int? ?? 0;
          if (newCount > _openRequestCount) {
            final diff = newCount - _openRequestCount;
            setState(() => _openRequestCount = newCount);
            if (kIsWeb) _jsSetAppBadge(newCount);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.inbox_rounded, color: Colors.white, size: 18),
                    const SizedBox(width: 10),
                    Text(
                      '$diff new request${diff > 1 ? 's' : ''} received',
                      style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
                duration: const Duration(seconds: 6),
                behavior: SnackBarBehavior.floating,
                backgroundColor: AppColors.textPrimary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            );
          } else {
            setState(() => _openRequestCount = newCount);
            if (kIsWeb) _jsSetAppBadge(newCount);
          }
        }
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_roleLoaded) {
      return const Scaffold(
        backgroundColor: AppColors.bgPrimary,
        body: Center(
          child: CircularProgressIndicator(
            color: AppColors.accent,
            strokeWidth: 1.5,
          ),
        ),
      );
    }

    final isRequester = _userRole == 'requester';

    final requestsTab = NavigationDestination(
      icon: Badge(
        isLabelVisible: !isRequester && _openRequestCount > 0,
        label: Text('$_openRequestCount', style: const TextStyle(fontSize: 10)),
        child: const Icon(Icons.inbox_outlined),
      ),
      selectedIcon: Badge(
        isLabelVisible: !isRequester && _openRequestCount > 0,
        label: Text('$_openRequestCount', style: const TextStyle(fontSize: 10)),
        child: const Icon(Icons.inbox_rounded),
      ),
      label: 'Requests',
    );

    final pages = isRequester
        ? [
            RequestsScreen(userRole: _userRole, onChanged: _refreshRequestCount),
            SettingsPage(themeController: widget.themeController, userRole: _userRole),
          ]
        : [
            const WorkOrderHome(),
            const DocumentsScreen(),
            const WorkOrderReportScreen(),
            RequestsScreen(userRole: _userRole, onChanged: _refreshRequestCount),
            SettingsPage(themeController: widget.themeController, userRole: _userRole),
          ];

    final destinations = isRequester
        ? [
            requestsTab,
            const NavigationDestination(icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded), label: 'Settings'),
          ]
        : [
            const NavigationDestination(icon: Icon(Icons.work_outline_rounded), selectedIcon: Icon(Icons.work_rounded), label: 'Orders'),
            const NavigationDestination(icon: Icon(Icons.description_outlined), selectedIcon: Icon(Icons.description_rounded), label: 'Documents'),
            const NavigationDestination(icon: Icon(Icons.bar_chart_outlined), selectedIcon: Icon(Icons.bar_chart_rounded), label: 'Reports'),
            requestsTab,
            const NavigationDestination(icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded), label: 'Settings'),
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
          destinations: destinations,
        ),
      ),
    );
  }
}

class SettingsPage extends StatefulWidget {
  final ThemeController themeController;
  final String userRole;
  const SettingsPage({super.key, required this.themeController, this.userRole = 'admin'});

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
    Color(0xFF1A1915), Color(0xFFCC785C), Color(0xFF15803D),
    Color(0xFF1D4ED8), Color(0xFF7C3AED),
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
    setState(() { version = info.version; buildNumber = info.buildNumber; });
  }

  Future<void> _checkUpdates() async {
    setState(() { checkingUpdate = true; updateMessage = ''; updateAvailable = false; });
    try {
      final res = await http.get(Uri.parse('${AppConfig.baseUrl}/version'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final latest = data['version'] as String;
        final hasUpdate = latest != version.split('+')[0];
        setState(() {
          updateAvailable = hasUpdate;
          updateMessage = hasUpdate ? 'Update available: $latest' : 'You are on the latest version';
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
    if (kIsWeb) _jsApplyPWAUpdate();
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: const Text('Create Account',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Email
              const Text('Email',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.textTertiary)),
              const SizedBox(height: 4),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.bgSurface2,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border, width: 0.5),
                ),
                child: TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                  decoration: const InputDecoration(
                    hintText: 'user@company.com',
                    hintStyle: TextStyle(fontSize: 13, color: AppColors.textTertiary),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Password
              const Text('Password',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.textTertiary)),
              const SizedBox(height: 4),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.bgSurface2,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border, width: 0.5),
                ),
                child: TextField(
                  controller: passCtrl,
                  obscureText: true,
                  style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                  decoration: const InputDecoration(
                    hintText: '••••••••',
                    hintStyle: TextStyle(fontSize: 13, color: AppColors.textTertiary),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              // Role selector
              const Text('Role',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.textTertiary)),
              const SizedBox(height: 6),
              Row(
                children: ['requester', 'tech'].map((role) {
                  final isSel = selectedRole == role;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setDlg(() => selectedRole = role),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        margin: EdgeInsets.only(right: role == 'requester' ? 6 : 0),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: isSel ? AppColors.textPrimary : AppColors.bgSurface2,
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(
                            color: isSel ? AppColors.textPrimary : AppColors.border2,
                            width: 0.5,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            role == 'requester' ? 'Requester' : 'Tech',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: isSel ? Colors.white : AppColors.textSecondary,
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
              child: const Text('Cancel'),
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
                          Uri.parse('${AppConfig.baseUrl}/admin/create-user'),
                          headers: {'Content-Type': 'application/json'},
                          body: jsonEncode({
                            'email': email,
                            'password': password,
                            'user_type': selectedRole,
                          }),
                        );
                        if (!ctx.mounted) return;
                        if (res.statusCode == 200) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text('Account created for $email'),
                            backgroundColor: AppColors.closedText,
                            behavior: SnackBarBehavior.floating,
                          ));
                        } else {
                          final body = jsonDecode(res.body);
                          setDlg(() => loading = false);
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(body['detail'] ?? 'Failed to create account'),
                            backgroundColor: AppColors.dangerText,
                            behavior: SnackBarBehavior.floating,
                          ));
                        }
                      } catch (e) {
                        setDlg(() => loading = false);
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: loading
                  ? const SizedBox(
                      width: 14, height: 14,
                      child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white),
                    )
                  : const Text('Create', style: TextStyle(fontSize: 13)),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Sign out', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        content: const Text('Are you sure you want to sign out?', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sign out')),
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
    final currentScale = widget.themeController.fontScale;

    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              const Text('Settings', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: AppColors.textPrimary, letterSpacing: -0.3)),
              const SizedBox(height: 16),

              // Profile card
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: AppColors.bgSurface2, borderRadius: BorderRadius.circular(14)),
                child: Row(
                  children: [
                    InitialsAvatar(name: nameInitials, size: 42, large: true),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(nameInitials, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                          const SizedBox(height: 2),
                          Text(email, style: const TextStyle(fontSize: 11, color: AppColors.textTertiary)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Account
              SectionLabel(text: 'Account'),
              SurfaceCard(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: SettingsRow(
                  icon: Icons.lock_outline_rounded,
                  label: 'Change password',
                  showDivider: false,
                  onTap: () => showDialog(context: context, builder: (_) => const ChangePasswordDialog()),
                ),
              ),

              const SizedBox(height: 12),

              // Appearance
              SectionLabel(text: 'Appearance'),
              SurfaceCard(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
                child: Column(
                  children: [

                    // Theme color row
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
                              duration: const Duration(milliseconds: 150),
                              width: isSel ? 22 : 18,
                              height: isSel ? 22 : 18,
                              margin: const EdgeInsets.only(left: 6),
                              decoration: BoxDecoration(
                                color: c,
                                shape: BoxShape.circle,
                                border: isSel
                                    ? Border.all(color: AppColors.textPrimary, width: 2)
                                    : Border.all(color: AppColors.border2, width: 0.5),
                              ),
                              child: isSel ? const Icon(Icons.check_rounded, color: Colors.white, size: 11) : null,
                            ),
                          );
                        }).toList(),
                      ),
                    ),

                    // Divider between rows
                    const Divider(height: 0, thickness: 0.5, color: AppColors.border),

                    // Font size row
                    _FontSizeRow(
                      currentScale: currentScale,
                      scales: _fontScales,
                      labels: _fontLabels,
                      onChanged: (scale) => widget.themeController.setFontScale(scale),
                    ),

                    const Divider(height: 0, thickness: 0.5, color: AppColors.border),

                    // Font type row
                    _FontTypeRow(
                      currentFamily: widget.themeController.fontFamily,
                      onChanged: (family) => widget.themeController.setFontFamily(family),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Notifications (admin & tech only)
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
                          content: const Text('Notifications disabled'),
                          backgroundColor: AppColors.dangerText,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
                              : 'Notifications blocked — check browser settings'),
                          backgroundColor: granted ? AppColors.closedText : AppColors.dangerText,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ));
                      }
                    },
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // User Management (admin only)
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
                const SizedBox(height: 12),
              ],

              // Application
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
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.textTertiary))
                      : const Icon(Icons.chevron_right_rounded, size: 16, color: AppColors.textTertiary),
                ),
              ),

              if (updateMessage.isNotEmpty) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    children: [
                      Text(updateMessage, style: const TextStyle(fontSize: 12, color: AppColors.textTertiary)),
                      if (updateAvailable) ...[
                        const SizedBox(width: 10),
                        GestureDetector(
                          onTap: _applyUpdate,
                          child: const Text('Update now', style: TextStyle(fontSize: 12, color: AppColors.accent, fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 20),

              // Sign out
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _signOut,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.dangerText,
                    side: const BorderSide(color: AppColors.dangerBorder, width: 0.5),
                    backgroundColor: AppColors.dangerBg,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Sign out', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                ),
              ),

              const SizedBox(height: 24),

              // Footer
              Center(
                child: Column(
                  children: [
                    const Text('Work Order', style: TextStyle(fontSize: 12, color: AppColors.textTertiary, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 3),
                    if (version.isNotEmpty)
                      Text('Version $version · Build $buildNumber', style: const TextStyle(fontSize: 10, color: AppColors.textTertiary)),
                    const SizedBox(height: 2),
                    const Text('Developed by Salah · 2026', style: TextStyle(fontSize: 10, color: AppColors.textTertiary)),
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

// ─── Font Type Row ────────────────────────────────────────────────────────────

class _FontTypeRow extends StatelessWidget {
  final String currentFamily;
  final ValueChanged<String> onChanged;

  const _FontTypeRow({required this.currentFamily, required this.onChanged});

  static TextStyle _previewStyle(String family) {
    return switch (family) {
      'Roboto'  => GoogleFonts.roboto(fontSize: 13, fontWeight: FontWeight.w500),
      'Poppins' => GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500),
      'Lato'    => GoogleFonts.lato(fontSize: 13, fontWeight: FontWeight.w500),
      'Nunito'  => GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w500),
      _         => GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500),
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
                width: 32, height: 32,
                decoration: BoxDecoration(color: AppColors.bgSurface2, borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.font_download_outlined, size: 15, color: AppColors.textSecondary),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Font type', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: AppColors.accentBg, borderRadius: BorderRadius.circular(10)),
                child: Text(
                  currentFamily,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.accent),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: kAvailableFonts.map((family) {
              final isSelected = currentFamily == family;
              return GestureDetector(
                onTap: () => onChanged(family),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
                      color: isSelected ? Colors.white : AppColors.textSecondary,
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

          // Label + current badge
          Row(
            children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(color: AppColors.bgSurface2, borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.text_fields_rounded, size: 15, color: AppColors.textSecondary),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Text size', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: AppColors.accentBg, borderRadius: BorderRadius.circular(10)),
                child: Text(
                  labels[scales.indexWhere((s) => (s - currentScale).abs() < 0.01).clamp(0, labels.length - 1)],
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.accent),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // 4 size buttons
          Row(
            children: List.generate(scales.length, (i) {
              final isSelected = (currentScale - scales[i]).abs() < 0.01;
              return Expanded(
                child: GestureDetector(
                  onTap: () => onChanged(scales[i]),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: EdgeInsets.only(right: i < scales.length - 1 ? 6 : 0),
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.accent : AppColors.bgSurface2,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(
                        color: isSelected ? AppColors.accent : AppColors.border2,
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
                            color: isSelected ? Colors.white : AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          labels[i],
                          style: TextStyle(
                            fontSize: 9,
                            color: isSelected ? Colors.white.withOpacity(0.7) : AppColors.textTertiary,
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
