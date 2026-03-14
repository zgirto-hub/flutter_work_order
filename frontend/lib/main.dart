import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/main_screen.dart';
import 'screens/login_screen.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';

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
        return MediaQuery(
          data: MediaQueryData.fromView(View.of(context)).copyWith(
            textScaler: TextScaler.linear(themeController.fontScale),
          ),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            title: 'Work Order',
            theme: AppTheme.light,
            home: AuthWrapper(themeController: themeController),
          ),
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
    return Container(
      color: AppColors.bgSurface2,
      child: Center(
        child: Container(
          width: 620,
          decoration: BoxDecoration(
            color: AppColors.bgSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border, width: 0.5),
            boxShadow: [
              BoxShadow(
                blurRadius: 40,
                color: Colors.black.withOpacity(0.06),
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: StreamBuilder<AuthState>(
              stream: Supabase.instance.client.auth.onAuthStateChange,
              builder: (context, snapshot) {
                final session = snapshot.data?.session;
                if (session == null) return const LoginScreen();
                return MainScreen(themeController: themeController);
              },
            ),
          ),
        ),
      ),
    );
  }
}
