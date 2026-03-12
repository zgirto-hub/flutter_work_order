import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../theme/theme_controller.dart';
import '../screens/Work_Orders/work_order_home.dart';
import '../screens/Documents/documents_screen.dart';
import '../features/reports/work_order_reports/screens/workorder_report_screen.dart';
import '../config.dart';

class MainScreen extends StatefulWidget {
  final ThemeController themeController;

  const MainScreen({super.key, required this.themeController});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      const WorkOrderHome(),
      const DocumentsScreen(),
      const WorkOrderReportScreen(),
      SettingsPage(themeController: widget.themeController),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _onItemTapped,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.work_outline),
            selectedIcon: Icon(Icons.work),
            label: "Work Orders",
          ),
          NavigationDestination(
            icon: Icon(Icons.description_outlined),
            selectedIcon: Icon(Icons.description),
            label: "Documents",
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart),
            label: "Reports",
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: "Settings",
          ),
        ],
      ),
    );
  }
}

class SettingsPage extends StatefulWidget {
  final ThemeController themeController;

  const SettingsPage({super.key, required this.themeController});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String version = "";

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    setState(() {
      version = "${info.version}+${info.buildNumber}";
    });
  }

  @override
Widget build(BuildContext context) {
  final user = Supabase.instance.client.auth.currentUser;
  final email = user?.email ?? "Unknown user";

  return SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        /// Profile Card
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          child: ListTile(
            leading: const CircleAvatar(
              radius: 22,
              child: Icon(Icons.person),
            ),
            title: const Text(
              "Logged in as",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(email),
          ),
        ),

        const SizedBox(height: 24),

        /// Theme Color Card
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                const Text(
                  "App Theme Color",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 14),

                Wrap(
                  spacing: 14,
                  children: [
                    _colorCircle(Colors.blue),
                    _colorCircle(Colors.green),
                    _colorCircle(Colors.purple),
                    _colorCircle(Colors.orange),
                    _colorCircle(Colors.red),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 24),

        /// Logout Button
        Center(
          child: ElevatedButton.icon(
            icon: const Icon(Icons.logout),
            label: const Text("Logout"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                horizontal: 32,
                vertical: 14,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text("Logout"),
                  content:
                      const Text("Are you sure you want to logout?"),
                  actions: [
                    TextButton(
                      onPressed: () =>
                          Navigator.pop(context, false),
                      child: const Text("Cancel"),
                    ),
                    TextButton(
                      onPressed: () =>
                          Navigator.pop(context, true),
                      child: const Text("Logout"),
                    ),
                  ],
                ),
              );

              if (confirm == true) {
                await Supabase.instance.client.auth.signOut();
              }
            },
          ),
        ),

        const SizedBox(height: 30),

        /// App Information
        Card(
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [

                Row(
                  mainAxisAlignment:
                      MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Version"),
                    Text(version),
                  ],
                ),

                const SizedBox(height: 8),

                Row(
                  mainAxisAlignment:
                      MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Build Date"),
                    Text(AppConfig.buildDate),
                  ],
                ),

                const Divider(height: 22),

                const Text(
                  "Developed by Salah",
                  style: TextStyle(
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
Widget _colorCircle(Color color) {
  return GestureDetector(
    onTap: () {
      widget.themeController.changeColor(color);
    },
    child: CircleAvatar(
      radius: 22,
      backgroundColor: color,
    ),
  );
}
}