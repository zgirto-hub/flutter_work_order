import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../theme/theme_controller.dart';
import '../screens/Work_Orders/work_order_home.dart';
import '../screens/Documents/documents_screen.dart';
import '../features/reports/work_order_reports/screens/workorder_report_screen.dart';
import '../config.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../widgets/change_password_dialog.dart';

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
  String latestVersion = "";
bool checkingUpdate = false;
String updateMessage = "";
  String version = "";
  Color selectedColor = Colors.blue;
  @override
  void initState() {
    super.initState();
    _loadVersion();
  }
Future<void> checkForUpdates() async {
  setState(() {
    checkingUpdate = true;
    updateMessage = "";
  });

  try {
    final response = await http.get(
      Uri.parse("${AppConfig.baseUrl}/version"),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);

      latestVersion = data["version"];

      if (latestVersion != version.split("+")[0]) {
        updateMessage = "Update available: $latestVersion";
      } else {
        updateMessage = "You are using the latest version";
      }
    } else {
      updateMessage = "Failed to check updates";
    }
  } catch (e) {
    updateMessage = "Update check error";
  }

  setState(() {
    checkingUpdate = false;
  });
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
                  ListTile(
            leading: const Icon(Icons.lock),
            title: const Text("Change Password"),
            onTap: () {
              showDialog(
                context: context,
                builder: (_) => const ChangePasswordDialog(),
              );
            },
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
                    

                        _colorCircle(Colors.green),
                        _colorCircle(Colors.purple),                       

                        /// Gradient themes
                        _colorCircle(Colors.blue, gradientEnd: Colors.purple),
                        _colorCircle(Colors.orange, gradientEnd: Colors.red),
                        _colorCircle(Colors.teal, gradientEnd: Colors.blue),
  ],
)
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        const Text(
          "App Information",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),

        const SizedBox(height: 14),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text("Version"),
            Text(version),
          ],
        ),

        const SizedBox(height: 8),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text("Build Date"),
            Text(AppConfig.buildDate),
          ],
        ),

        const SizedBox(height: 16),

        Center(
          child: ElevatedButton.icon(
            icon: const Icon(Icons.system_update),
            label: const Text("Check for Updates"),
            onPressed: checkingUpdate ? null : checkForUpdates,
          ),
        ),

        const SizedBox(height: 10),

        if (checkingUpdate)
          const Center(
            child: CircularProgressIndicator(),
          ),

        if (updateMessage.isNotEmpty)
          Center(
            child: Text(
              updateMessage,
              style: const TextStyle(
                color: Colors.grey,
              ),
            ),
          ),

        const Divider(height: 22),

        const Center(
          child: Text(
            "Developed by Salah",
            style: TextStyle(
              color: Colors.grey,
            ),
          ),
        ),
      ],
    ),
  ),
)
      ],
    ),
  );
}
Widget _colorCircle(Color color, {Color? gradientEnd}) {
  final isSelected = selectedColor == color;

  return GestureDetector(
    onTap: () {
      setState(() {
        selectedColor = color;
      });

      widget.themeController.changeColor(color);
    },
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: isSelected ? Border.all(color: Colors.black, width: 2) : null,
      ),
      child: AnimatedScale(
        scale: isSelected ? 1.15 : 1.0,
        duration: const Duration(milliseconds: 200),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: gradientEnd != null
                    ? LinearGradient(
                        colors: [color, gradientEnd],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: gradientEnd == null ? color : null,
              ),
            ),
            if (isSelected)
              const Icon(
                Icons.check,
                color: Colors.white,
                size: 20,
              ),
          ],
        ),
      ),
    ),
  );
}}