import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../config.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  String version = '';
  String buildNumber = '';
  bool _obscure = true;
  bool _rememberMe = false;
  bool _isLoading = false;

  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final supabase = Supabase.instance.client;

  static const _keyEmail = 'saved_email';
  static const _keyRemember = 'remember_me';

  @override
  void initState() {
    super.initState();
    _loadAppInfo();
    _loadSavedCredentials();
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadAppInfo() async {
    final info = await PackageInfo.fromPlatform();
    setState(() { version = info.version; buildNumber = info.buildNumber; });
  }

  Future<void> _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final remember = prefs.getBool(_keyRemember) ?? false;
    final savedEmail = prefs.getString(_keyEmail) ?? '';
    if (remember && savedEmail.isNotEmpty) {
      setState(() { _rememberMe = true; emailController.text = savedEmail; });
    }
  }

  Future<void> _saveCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    if (_rememberMe) {
      await prefs.setString(_keyEmail, emailController.text.trim());
      await prefs.setBool(_keyRemember, true);
    } else {
      await prefs.remove(_keyEmail);
      await prefs.setBool(_keyRemember, false);
    }
  }

  Future<void> _signIn() async {
    final email = emailController.text.trim();
    final password = passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      _showSnack('Please enter your email and password', isError: true);
      return;
    }
    setState(() => _isLoading = true);
    try {
      await supabase.auth.signInWithPassword(email: email, password: password);
      await _saveCredentials();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showSnack(_friendlyError(e.toString()), isError: true);
    }
  }

  String _friendlyError(String e) {
    if (e.contains('Invalid login')) return 'Incorrect email or password';
    if (e.contains('Email not confirmed')) return 'Please confirm your email first';
    return 'Sign in failed. Please try again.';
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? AppColors.dangerText : AppColors.closedText,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  Future<void> _showResetPasswordDialog() async {
    final resetCtrl = TextEditingController(text: emailController.text);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.bgSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Reset password', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text("We'll send a reset link to your email.", style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 14),
          TextField(controller: resetCtrl, style: const TextStyle(fontSize: 13), decoration: const InputDecoration(labelText: 'Email address')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final email = resetCtrl.text.trim();
              if (email.isEmpty) return;
              await supabase.auth.resetPasswordForEmail(email);
              if (!mounted) return;
              Navigator.pop(context);
              _showSnack('Reset link sent');
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
            child: AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  Center(
                    child: Container(
                      width: 52, height: 52,
                      decoration: BoxDecoration(color: AppColors.textPrimary, borderRadius: BorderRadius.circular(16)),
                      child: const Icon(Icons.description_rounded, color: Colors.white, size: 26),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Center(child: Text('Work Order [1.2]', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: AppColors.textPrimary, letterSpacing: -0.4))),
                  const SizedBox(height: 6),
                  const Center(child: Text('Sign in to your account', style: TextStyle(fontSize: 13, color: AppColors.textSecondary))),
                  const SizedBox(height: 32),

                  const _InputLabel(label: 'Email address'),
                  const SizedBox(height: 6),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email, AutofillHints.username],
                    textInputAction: TextInputAction.next,
                    style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                    decoration: const InputDecoration(hintText: 'you@company.com'),
                  ),
                  const SizedBox(height: 14),

                  const _InputLabel(label: 'Password'),
                  const SizedBox(height: 6),
                  TextField(
                    controller: passwordController,
                    obscureText: _obscure,
                    autofillHints: const [AutofillHints.password],
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _signIn(),
                    style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      hintText: '',
                      suffixIcon: GestureDetector(
                        onTap: () => setState(() => _obscure = !_obscure),
                        child: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 16, color: AppColors.textTertiary),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      GestureDetector(
                        onTap: () => setState(() => _rememberMe = !_rememberMe),
                        child: Row(children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: 18, height: 18,
                            decoration: BoxDecoration(
                              color: _rememberMe ? AppColors.textPrimary : AppColors.bgSurface,
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(color: _rememberMe ? AppColors.textPrimary : AppColors.border2, width: 0.5),
                            ),
                            child: _rememberMe ? const Icon(Icons.check_rounded, color: Colors.white, size: 12) : null,
                          ),
                          const SizedBox(width: 7),
                          const Text('Remember me', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                        ]),
                      ),
                      GestureDetector(
                        onTap: _showResetPasswordDialog,
                        child: const Text('Forgot password?', style: TextStyle(fontSize: 12, color: AppColors.textTertiary)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _signIn,
                      child: _isLoading
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Sign in'),
                    ),
                  ),
                  const SizedBox(height: 12),

                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => _showSnack('Contact Salah to create an account'),
                      child: const Text('Create account'),
                    ),
                  ),

                  const SizedBox(height: 40),

                  Center(child: Column(children: [
                    const Text('Developed by Salah © 2026', style: TextStyle(fontSize: 11, color: AppColors.textTertiary)),
                    if (version.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text('Version $version (Build $buildNumber)', style: const TextStyle(fontSize: 10, color: AppColors.textTertiary)),
                    ],
                    if (AppConfig.buildDate.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text('Build: ${AppConfig.buildDate}', style: const TextStyle(fontSize: 10, color: AppColors.textTertiary)),
                    ],
                  ])),
                ],
              ),
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
    return Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textSecondary));
  }
}
