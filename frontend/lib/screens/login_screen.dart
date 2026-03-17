import 'dart:math' show pi;
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

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
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

  late final AnimationController _entranceCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );

  Animation<double> _fadeAt(double start, double end) => CurvedAnimation(
        parent: _entranceCtrl,
        curve: Interval(start, end, curve: Curves.easeOut),
      );

  Animation<Offset> _slideAt(double start, double end) =>
      Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero).animate(
        CurvedAnimation(
          parent: _entranceCtrl,
          curve: Interval(start, end, curve: Curves.easeOutCubic),
        ),
      );

  @override
  void initState() {
    super.initState();
    _loadAppInfo();
    _loadSavedCredentials();
    WidgetsBinding.instance.addPostFrameCallback((_) => _entranceCtrl.forward());
  }

  @override
  void dispose() {
    _entranceCtrl.dispose();
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
          Text("We'll send a reset link to your email.", style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 14),
          TextField(controller: resetCtrl, style: const TextStyle(fontSize: 13), decoration: const InputDecoration(labelText: 'Email address')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final email = resetCtrl.text.trim();
              if (email.isEmpty) return;
              final nav = Navigator.of(context);
              await supabase.auth.resetPasswordForEmail(email);
              if (!mounted) return;
              nav.pop();
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

                  // ── Logo + title ───────────────────────────────────────
                  FadeTransition(
                    opacity: _fadeAt(0.0, 0.55),
                    child: SlideTransition(
                      position: _slideAt(0.0, 0.55),
                      child: Column(
                        children: [
                          const Center(child: _AppLogo()),
                          const SizedBox(height: 24),
                          Center(child: Text('Work Order', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: AppColors.textPrimary, letterSpacing: -0.4))),
                          const SizedBox(height: 6),
                          Center(child: Text('Sign in to your account', style: TextStyle(fontSize: 13, color: AppColors.textSecondary))),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // ── Form fields ────────────────────────────────────────
                  FadeTransition(
                    opacity: _fadeAt(0.15, 0.7),
                    child: SlideTransition(
                      position: _slideAt(0.15, 0.7),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _InputLabel(label: 'Email address'),
                          const SizedBox(height: 6),
                          TextField(
                            controller: emailController,
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [AutofillHints.email, AutofillHints.username],
                            textInputAction: TextInputAction.next,
                            style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
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
                            style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
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
                                  Text('Remember me', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                                ]),
                              ),
                              GestureDetector(
                                onTap: _showResetPasswordDialog,
                                child: Text('Forgot password?', style: TextStyle(fontSize: 12, color: AppColors.textTertiary)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Buttons + footer ───────────────────────────────────
                  FadeTransition(
                    opacity: _fadeAt(0.3, 0.9),
                    child: SlideTransition(
                      position: _slideAt(0.3, 0.9),
                      child: Column(
                        children: [
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

                          Column(children: [
                            Text('Developed by Salah © 2026', style: TextStyle(fontSize: 11, color: AppColors.textTertiary)),
                            if (version.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text('Version $version (Build $buildNumber)', style: TextStyle(fontSize: 10, color: AppColors.textTertiary)),
                            ],
                            if (AppConfig.buildDate.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text('Build: ${AppConfig.buildDate}', style: TextStyle(fontSize: 10, color: AppColors.textTertiary)),
                            ],
                          ]),
                        ],
                      ),
                    ),
                  ),
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
    return Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textSecondary));
  }
}

// ── App Logo ───────────────────────────────────────────────────────────────────
// Claude.ai-inspired: warm terracotta gradient container with a triskelion mark
// (3 rounded pills at 120° intervals — the same compositional logic Claude uses).

class _AppLogo extends StatelessWidget {
  const _AppLogo();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFDA8C6A), Color(0xFFAF5335)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFCC785C).withValues(alpha: 0.38),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: const CustomPaint(painter: _LogoMarkPainter()),
    );
  }
}

class _LogoMarkPainter extends CustomPainter {
  const _LogoMarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.92)
      ..style = PaintingStyle.fill;

    canvas.save();
    canvas.translate(w / 2, h / 2);

    // 3 rounded pills at 120° intervals — Claude.ai-inspired triskelion mark
    for (int i = 0; i < 3; i++) {
      canvas.save();
      canvas.rotate(i * (2 * pi / 3));

      final rr = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(0, -(h * 0.135)),
          width: w * 0.205,
          height: h * 0.46,
        ),
        Radius.circular(w * 0.103),
      );
      canvas.drawRRect(rr, paint);
      canvas.restore();
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_LogoMarkPainter oldDelegate) => false;
}
