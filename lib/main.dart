import 'screens/main_screen.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/login_screen.dart';

import './theme/theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://rydrqsjofoulwdtwfbgv.supabase.co',
    anonKey: 'sb_publishable_smzkBX6r1G8TwlmQbhs7lw_bZgmZUC7',
  );

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  MyApp({super.key});

  final ThemeController themeController = ThemeController();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: themeController,
      builder: (context, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: themeController.primaryColor,
            ),
            useMaterial3: true,
          ),
          home: AuthWrapper(themeController: themeController),
        );
      },
    );
  }
}

class AuthWrapper extends StatelessWidget {
  final ThemeController themeController;

  const AuthWrapper({super.key, required this.themeController});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = snapshot.data?.session;

        if (session == null) {
          return const LoginScreen();
        } else {
          return MainScreen(themeController: themeController);
        }
      },
    );
  }
}
