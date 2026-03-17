import 'package:flutter/material.dart';
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
import '../screens/dashboard_screen.dart';
import '../screens/more_screen.dart';
import '../config.dart';
import '../services/request_service.dart';
import '../services/onesignal_service.dart';
import '../services/activity_log_service.dart';
import '../screens/settings_page.dart';


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
    try {
      await ActivityLogService().logSignIn(email);
    } catch (_) {}

    if (role != 'requester') {
      _refreshRequestCount();
      _startPolling();
    }
    OneSignalService.subscribe(email, role);
  }

  Future<void> _refreshRequestCount() async {
    try {
      final res = await http
          .get(Uri.parse('${AppConfig.baseUrl}/requests/count-open'));
      if (!mounted) return;
      if (res.statusCode == 200) {
        final count = jsonDecode(res.body)['count'] as int? ?? 0;
        setState(() => _openRequestCount = count);
      }
    } catch (_) {}
  }

  void _startPolling() {
    _pollTimer =
        Timer.periodic(const Duration(seconds: 20), (_) async {
      try {
        final res = await http
            .get(Uri.parse('${AppConfig.baseUrl}/requests/count-open'));
        if (!mounted) return;
        if (res.statusCode == 200) {
          final newCount = jsonDecode(res.body)['count'] as int? ?? 0;
          if (newCount > _openRequestCount) {
            final diff = newCount - _openRequestCount;
            setState(() => _openRequestCount = newCount);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    Icon(Icons.inbox_rounded,
                        color: Colors.white, size: 18),
                    SizedBox(width: 10),
                    Text(
                      '$diff new request${diff > 1 ? 's' : ''} received',
                      style: TextStyle(
                          fontSize: 13,
                          color: Colors.white,
                          fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
                duration: const Duration(seconds: 6),
                behavior: SnackBarBehavior.floating,
                backgroundColor: AppColors.textPrimary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            );
          } else {
            setState(() => _openRequestCount = newCount);
          }
        }
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_roleLoaded) {
      return Scaffold(
        backgroundColor: AppColors.bgPrimary,
        body: Center(
          child: CircularProgressIndicator(
              color: AppColors.accent, strokeWidth: 1.5),
        ),
      );
    }

    final isRequester = _userRole == 'requester';

    // ── Requester layout: simple 2 tabs ───────────────────────────────────
    if (isRequester) {
      final pages = [
        RequestsScreen(
            userRole: _userRole, onChanged: _refreshRequestCount),
        SettingsPage(
            themeController: widget.themeController,
            userRole: _userRole),
      ];

      return Scaffold(
        body: _AnimatedTabBody(index: _index, children: pages),
        bottomNavigationBar: _BottomNav(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: [
            NavigationDestination(
              icon: Badge(
                isLabelVisible: _openRequestCount > 0,
                label: Text('$_openRequestCount',
                    style: TextStyle(fontSize: 10)),
                child: Icon(Icons.inbox_outlined),
              ),
              selectedIcon: Badge(
                isLabelVisible: _openRequestCount > 0,
                label: Text('$_openRequestCount',
                    style: TextStyle(fontSize: 10)),
                child: Icon(Icons.inbox_rounded),
              ),
              label: 'Requests',
            ),
            const NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(Icons.person_rounded),
              label: 'Settings',
            ),
          ],
        ),
      );
    }

    // ── Admin / Tech layout: Plan C (Dashboard, Orders, Requests, More) ──
    final requestsDestination = NavigationDestination(
      icon: Badge(
        isLabelVisible: _openRequestCount > 0,
        label: Text('$_openRequestCount',
            style: TextStyle(fontSize: 10)),
        child: Icon(Icons.inbox_outlined),
      ),
      selectedIcon: Badge(
        isLabelVisible: _openRequestCount > 0,
        label: Text('$_openRequestCount',
            style: TextStyle(fontSize: 10)),
        child: Icon(Icons.inbox_rounded),
      ),
      label: 'Requests',
    );

    final pages = [
      // Tab 0: Dashboard
      DashboardScreen(
        userRole: _userRole,
        openRequestCount: _openRequestCount,
        onNavigate: (index) => setState(() => _index = index),
      ),
      // Tab 1: Work Orders
      const WorkOrderHome(),
      // Tab 2: Requests
      RequestsScreen(
          userRole: _userRole, onChanged: _refreshRequestCount),
      // Tab 3: More
      MoreScreen(
        themeController: widget.themeController,
        userRole: _userRole,
      ),
    ];

    return Scaffold(
      body: _AnimatedTabBody(index: _index, children: pages),
      bottomNavigationBar: _BottomNav(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: 'Dashboard',
          ),
          const NavigationDestination(
            icon: Icon(Icons.work_outline_rounded),
            selectedIcon: Icon(Icons.work_rounded),
            label: 'Orders',
          ),
          requestsDestination,
          const NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view_rounded),
            label: 'More',
          ),
        ],
      ),
    );
  }
}

// ── Bottom Nav wrapper ────────────────────────────────────────────────────────

class _BottomNav extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<NavigationDestination> destinations;

  const _BottomNav({
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        border:
            Border(top: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      child: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: onDestinationSelected,
        backgroundColor: AppColors.bgSurface,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        height: 60,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: destinations,
      ),
    );
  }
}

// ── Animated Tab Body ─────────────────────────────────────────────────────────
// Keeps all tabs mounted (like IndexedStack) and animates the newly-shown tab
// with a subtle fade + slide-up — matching Claude.ai's navigation feel.

class _AnimatedTabBody extends StatefulWidget {
  final int index;
  final List<Widget> children;

  const _AnimatedTabBody({required this.index, required this.children});

  @override
  State<_AnimatedTabBody> createState() => _AnimatedTabBodyState();
}

class _AnimatedTabBodyState extends State<_AnimatedTabBody>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );
  late final Animation<double> _fade =
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 0.025),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));

  @override
  void initState() {
    super.initState();
    _ctrl.value = 1.0;
  }

  @override
  void didUpdateWidget(_AnimatedTabBody old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) {
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: IndexedStack(
          index: widget.index,
          children: widget.children,
        ),
      ),
    );
  }
}

// ── Settings Page ─────────────────────────────────────────────────────────────
// Kept here since it's used by both MoreScreen and requester layout
