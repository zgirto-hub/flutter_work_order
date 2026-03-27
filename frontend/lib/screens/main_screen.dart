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
import '../screens/Work_Orders/add_work_order.dart';
import '../screens/more_screen.dart';
import '../screens/dashboard_screen.dart';
import '../config.dart';
import '../services/work_order_service.dart';
import '../models/work_order.dart';
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
  int _openWOCount = 0;
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
    try {
      final res = await http.get(
        Uri.parse('${AppConfig.baseUrl}/user-role?email=${Uri.encodeComponent(email)}'),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        _userRole = data['user_type'] ?? 'admin';
      }
    } catch (_) {
      _userRole = 'admin';
    }
    if (!mounted) return;
    setState(() {
      _index = 0;
      _roleLoaded = true;
    });
    try {
      await ActivityLogService().logSignIn(email);
    } catch (_) {}

    _refreshWOCount();
    _startPolling();
    OneSignalService.subscribe(email, _userRole);
  }

  String get _email =>
      Supabase.instance.client.auth.currentUser?.email ?? '';

  Future<void> _refreshWOCount() async {
    try {
      final res = await http.get(
        Uri.parse('${AppConfig.baseUrl}/work-orders?email=${Uri.encodeComponent(_email)}&user_role=${Uri.encodeComponent(_userRole)}'),
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final workOrders = data['work_orders'] as List? ?? [];
        final openCount = workOrders.where((wo) => wo['status'] != 'Closed').length;
        setState(() => _openWOCount = openCount);
      }
    } catch (_) {}
  }

  void _startPolling() {
    _pollTimer = Timer.periodic(const Duration(seconds: 20), (_) async {
      try {
        final res = await http.get(
          Uri.parse('${AppConfig.baseUrl}/work-orders?email=${Uri.encodeComponent(_email)}&user_role=${Uri.encodeComponent(_userRole)}'),
        );
        if (!mounted) return;
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final workOrders = data['work_orders'] as List? ?? [];
          final newCount = workOrders.where((wo) => wo['status'] != 'Closed').length;
          if (newCount > _openWOCount) {
            final diff = newCount - _openWOCount;
            setState(() => _openWOCount = newCount);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    Icon(Icons.work_outline_rounded, color: Colors.white, size: 18),
                    SizedBox(width: 10),
                    Text(
                      '$diff new work order${diff > 1 ? 's' : ''}',
                      style: TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w500),
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
            setState(() => _openWOCount = newCount);
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
          child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 1.5),
        ),
      );
    }

    final isRequester = _userRole == 'requester';

    if (isRequester) {
      final pages = [
        WorkOrderHome(userRole: _userRole, isRequesterView: true),
        SettingsPage(themeController: widget.themeController, userRole: _userRole),
      ];

      final now = DateTime.now();
      final jobNo = 'WO${now.year.toString().substring(2)}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';

      return Scaffold(
        body: _AnimatedTabBody(index: _index, children: pages),
        floatingActionButton: FloatingActionButton(
          onPressed: () async {
            final result = await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => AddWorkOrderScreen(
                userRole: _userRole,
                autoGeneratedJobNo: jobNo,
              )),
            );
            if (result is WorkOrder) _refreshWOCount();
          },
          backgroundColor: AppColors.accent,
          child: Icon(Icons.add, color: Colors.white),
        ),
        bottomNavigationBar: _BottomNav(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: [
            NavigationDestination(
              icon: Badge(
                isLabelVisible: _openWOCount > 0,
                label: Text('$_openWOCount', style: TextStyle(fontSize: 10)),
                child: Icon(Icons.report_outlined),
              ),
              selectedIcon: Badge(
                isLabelVisible: _openWOCount > 0,
                label: Text('$_openWOCount', style: TextStyle(fontSize: 10)),
                child: Icon(Icons.report_rounded),
              ),
              label: 'Report Issue',
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

    final pages = [
      DashboardScreen(
        userRole: _userRole,
        openRequestCount: _openWOCount,
        onNavigate: (index) => setState(() => _index = index),
      ),
      WorkOrderHome(onWorkOrderCreated: _refreshWOCount),
      MoreScreen(themeController: widget.themeController, userRole: _userRole),
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
        border: Border(top: BorderSide(color: AppColors.border, width: 0.5)),
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
  late final Animation<double> _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
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
        child: IndexedStack(index: widget.index, children: widget.children),
      ),
    );
  }
}
