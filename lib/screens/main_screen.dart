import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/theme_controller.dart';
import 'work_order_home.dart';
import 'documents_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  Future<void> _logout() async {
    await Supabase.instance.client.auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
final pages = [
  const WorkOrderHome(), // Dashboard
  const Center(child: Text("Work Orders")), // Work Orders
  const DocumentsScreen(), // Documents
  SettingsPage(themeController: widget.themeController),
];
    return Scaffold(
      
      body: pages[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _onItemTapped,
        destinations: const [
  NavigationDestination(
    icon: Icon(Icons.dashboard_outlined),
    selectedIcon: Icon(Icons.dashboard),
    label: "Dashboard",
  ),
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
    icon: Icon(Icons.settings_outlined),
    selectedIcon: Icon(Icons.settings),
    label: "Settings",
  ),
],
      ),
    );
  }
}
class SettingsPage extends StatelessWidget {
  final ThemeController themeController;

  const SettingsPage({super.key, required this.themeController});

  Future<void> _logout(BuildContext context) async {
    await Supabase.instance.client.auth.signOut();
  }

 @override
Widget build(BuildContext context) {
  return Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Choose App Color",
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),

        const SizedBox(height: 20),

        Wrap(
          spacing: 16,
          children: [
            _colorCircle(Colors.blue),
            _colorCircle(Colors.green),
            _colorCircle(Colors.purple),
            _colorCircle(Colors.orange),
            _colorCircle(Colors.red),
          ],
        ),

        const SizedBox(height: 40),
        const Divider(),
        const SizedBox(height: 10),

        ListTile(
          leading: const Icon(Icons.logout, color: Colors.red),
          title: const Text("Logout"),
          onTap: () async {
            final confirm = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text("Logout"),
                content: const Text("Are you sure you want to logout?"),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text("Cancel"),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
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
      ],
    ),
  );
}
  Widget _colorCircle(Color color) {
    return GestureDetector(
      onTap: () {
        themeController.changeColor(color);
      },
      child: CircleAvatar(
        radius: 22,
        backgroundColor: color,
      ),
    );
  }
}
