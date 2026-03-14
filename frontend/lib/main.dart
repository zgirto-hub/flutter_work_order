import 'screens/main_screen.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/login_screen.dart';
import './theme/theme_controller.dart';
import 'package:google_fonts/google_fonts.dart';

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
        final themeData = ThemeData(
          useMaterial3: true,

          /// Background
          scaffoldBackgroundColor: const Color(0xFFF4F6FA),

          /// Color scheme
          colorScheme: ColorScheme.fromSeed(
            seedColor: themeController.color,
            brightness: Brightness.light,
          ),

          /// Google Fonts
          textTheme: GoogleFonts.interTextTheme().copyWith(
            titleLarge: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Color(0xFF111827),
            ),
            bodyLarge: const TextStyle(
              fontSize: 15,
              color: Color(0xFF111827),
            ),
            bodyMedium: const TextStyle(
              fontSize: 14,
              color: Color(0xFF6B7280),
            ),
          ),

          /// Cards
          cardTheme: CardThemeData(
            elevation: 0,
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),

          /// Buttons
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              elevation: 0,
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 14,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),

          /// Input fields
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            hintStyle: const TextStyle(
              color: Color(0xFF9CA3AF),
              fontSize: 14,
            ),
          ),

          /// Chips (filters)
          chipTheme: ChipThemeData(
            backgroundColor: const Color(0xFFF3F4F6),
            selectedColor: themeController.color.withOpacity(0.15),
            labelStyle: const TextStyle(
              fontWeight: FontWeight.w500,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        );

        return AnimatedTheme(
          data: themeData,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: themeData,
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
      color: const Color(0xFFE5E7EB), // browser background
      child: Center(
        child: Container(
          width: 620,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                blurRadius: 30,
                color: Colors.black.withOpacity(0.08),
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: StreamBuilder<AuthState>(
              stream: Supabase.instance.client.auth.onAuthStateChange,
              builder: (context, snapshot) {
                final session = snapshot.data?.session;

                if (session == null) {
                  return const LoginScreen();
                } else {
                  return MainScreen(themeController: themeController);
                }
              },
            ),
          ),
        ),
      ),
    );
  }
}