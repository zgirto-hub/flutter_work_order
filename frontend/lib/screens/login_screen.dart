import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../theme/app_theme.dart';
import '../../config.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  String version = '';
  String buildNumber = '';
  bool _obscure = true;

  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _loadAppInfo();
  }

  Future<void> _loadAppInfo() async {
    final info = await PackageInfo.fromPlatform();
    setState(() {
      version = info.version;
      buildNumber = info.buildNumber;
    });
  }

  Future<void> _signIn() async {
    try {
      await supabase.auth.signInWithPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          backgroundColor: AppColors.dangerText,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  Future<void> _showResetPasswordDialog() async {
    final resetCtrl = TextEditingController(text: emailController.text);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.bgSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Reset password', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("We'll send a reset link to your email.", style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(height: 14),
            TextField(
              controller: resetCtrl,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(labelText: 'Email address'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              final email = resetCtrl.text.trim();
              if (email.isEmpty) return;
              await supabase.auth.resetPasswordForEmail(email);
              if (!mounted) return;
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Reset link sent'),
                  backgroundColor: AppColors.closedText,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              );
            },
            child: const Text('Send link'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // ── Logo ─────────────────────────────────────
                Center(
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: AppColors.textPrimary,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.description_rounded, color: Colors.white, size: 26),
                  ),
                ),

                const SizedBox(height: 24),

                // ── Heading ───────────────────────────────────
                const Center(
                  child: Text(
                    'Work Order',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: AppColors.textPrimary, letterSpacing: -0.4),
                  ),
                ),
                const SizedBox(height: 6),
                const Center(
                  child: Text(
                    'Sign in to your account',
                    style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  ),
                ),

                const SizedBox(height: 32),

                // ── Email ─────────────────────────────────────
                _InputLabel(label: 'Email address'),
                const SizedBox(height: 6),
                TextField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                  decoration: const InputDecoration(hintText: 'you@company.com'),
                ),

                const SizedBox(height: 14),

                // ── Password ──────────────────────────────────
                _InputLabel(label: 'Password'),
                const SizedBox(height: 6),
                TextField(
                  controller: passwordController,
                  obscureText: _obscure,
                  style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    hintText: '••••••••',
                    suffixIcon: GestureDetector(
                      onTap: () => setState(() => _obscure = !_obscure),
                      child: Icon(
                        _obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        size: 16,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                // ── Forgot ────────────────────────────────────
                Align(
                  alignment: Alignment.centerRight,
                  child: GestureDetector(
                    onTap: _showResetPasswordDialog,
                    child: const Text(
                      'Forgot password?',
                      style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // ── Sign In ───────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _signIn,
                    child: const Text('Sign in'),
                  ),
                ),

                const SizedBox(height: 12),

                // ── Create account ────────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('Contact Salah to create an account'),
                          behavior: SnackBarBehavior.floating,
                          backgroundColor: AppColors.pendingText,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      );
                    },
                    child: const Text('Create account'),
                  ),
                ),

                const SizedBox(height: 40),

                // ── Footer ────────────────────────────────────
                Center(
                  child: Column(
                    children: [
                      const Text(
                        'Developed by Salah © 2026',
                        style: TextStyle(fontSize: 11, color: AppColors.textTertiary),
                      ),
                      if (version.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          'Version $version (Build $buildNumber)',
                          style: const TextStyle(fontSize: 10, color: AppColors.textTertiary),
                        ),
                      ],
                      if (AppConfig.buildDate.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Build: ${AppConfig.buildDate}',
                          style: const TextStyle(fontSize: 10, color: AppColors.textTertiary),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InputLabel extends StatelessWidget {
  final String label;
  const _InputLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textSecondary),
    );
  }
}
