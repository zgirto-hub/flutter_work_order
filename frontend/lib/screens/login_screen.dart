import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/download_helper_mobile.dart'
    if (dart.library.js_interop) '../services/download_helper_web.dart';
import '../theme/app_theme.dart';
import '../config.dart';
import '../services/user_service.dart';
import 'reports/html_preview_screen.dart';
// Registration removed - admin creates all accounts

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
    duration: const Duration(milliseconds: 800),
  );

  Animation<double> _fadeAt(double start, double end) => CurvedAnimation(
        parent: _entranceCtrl,
        curve: Interval(start, end, curve: Curves.easeOut),
      );

  Animation<Offset> _slideAt(double start, double end) =>
      Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero).animate(
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

  void _openIntro() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const HtmlPreviewScreen(
        assetPath: 'assets/work_order_system_intro.html',
        title: 'About this system',
      ),
    ));
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
    final userService = UserService();
    bool sending = false;
    String? errorText;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: AppColors.bgSurface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: const Text('Reset password', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text("We'll send a reset link to your email.", style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(height: 14),
            TextField(controller: resetCtrl, style: const TextStyle(fontSize: 13), decoration: const InputDecoration(labelText: 'Email address')),
            if (errorText != null) ...[
              const SizedBox(height: 8),
              Text(errorText!, style: TextStyle(fontSize: 11, color: AppColors.dangerText)),
            ],
          ]),
          actions: [
            TextButton(onPressed: sending ? null : () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: sending ? null : () async {
                final email = resetCtrl.text.trim();
                if (email.isEmpty) {
                  setDlg(() => errorText = 'Please enter your email');
                  return;
                }
                setDlg(() { errorText = null; sending = true; });
                try {
                  await userService.requestPasswordReset(email);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) _showSnack('Reset link sent to your email');
                } catch (e) {
                  setDlg(() {
                    errorText = e.toString().replaceFirst('Exception: ', '');
                    sending = false;
                  });
                }
              },
              child: sending
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white))
                  : const Text('Send link'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final topPadding = MediaQuery.of(context).padding.top;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // ── Gradient background ──────────────────────────────────────
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.accent.withValues(alpha: 0.08),
                    AppColors.bgPrimary,
                    AppColors.bgPrimary,
                  ],
                  stops: const [0.0, 0.4, 1.0],
                ),
              ),
            ),
          ),

          // ── Decorative top accent bar ────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: topPadding + 4,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFE89977), Color(0xFFCC785C), Color(0xFFB85E3F)],
                ),
              ),
            ),
          ),

          // ── Main content ─────────────────────────────────────────────
          SingleChildScrollView(
            padding: EdgeInsets.only(
              top: topPadding + 24,
              left: 24,
              right: 24,
              bottom: 40,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(height: screenHeight * 0.04),

                      // ── Brand header ────────────────────────────────
                      FadeTransition(
                        opacity: _fadeAt(0.0, 0.5),
                        child: SlideTransition(
                          position: _slideAt(0.0, 0.5),
                          child: Column(
                            children: [
                              Text(
                                'Work Order',
                                style: TextStyle(
                                  fontSize: 30,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                  letterSpacing: -0.8,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Workflow Management',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: AppColors.textTertiary,
                                  fontWeight: FontWeight.w400,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 40),

                      // ── Form card ───────────────────────────────────
                      FadeTransition(
                        opacity: _fadeAt(0.1, 0.65),
                        child: SlideTransition(
                          position: _slideAt(0.1, 0.65),
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.bgSurface,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: AppColors.border,
                                width: 0.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.isDark
                                      ? Colors.black.withValues(alpha: 0.3)
                                      : const Color(0xFF1A1915).withValues(alpha: 0.06),
                                  blurRadius: 24,
                                  offset: const Offset(0, 8),
                                  spreadRadius: -4,
                                ),
                              ],
                            ),
                            padding: const EdgeInsets.all(28),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Welcome back',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Sign in to continue to your workspace',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 28),

                                // ── Email field ───────────────────────
                                const _InputLabel(label: 'Email'),
                                const SizedBox(height: 8),
                                TextField(
                                  controller: emailController,
                                  keyboardType: TextInputType.emailAddress,
                                  autofillHints: const [AutofillHints.email],
                                  textInputAction: TextInputAction.next,
                                  style: TextStyle(fontSize: 14, color: AppColors.textPrimary),
                                  decoration: InputDecoration(
                                    hintText: 'name@company.com',
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                    fillColor: AppColors.bgSurface2,
                                  ),
                                ),
                                const SizedBox(height: 20),

                                // ── Password field ────────────────────
                                const _InputLabel(label: 'Password'),
                                const SizedBox(height: 8),
                                TextField(
                                  controller: passwordController,
                                  obscureText: _obscure,
                                  autofillHints: const [AutofillHints.password],
                                  textInputAction: TextInputAction.done,
                                  onSubmitted: (_) => _signIn(),
                                  style: TextStyle(fontSize: 14, color: AppColors.textPrimary),
                                  decoration: InputDecoration(
                                    hintText: '••••••••',
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                    fillColor: AppColors.bgSurface2,
                                    suffixIcon: GestureDetector(
                                      onTap: () => setState(() => _obscure = !_obscure),
                                      child: Icon(
                                        _obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                        size: 18,
                                        color: AppColors.textTertiary,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),

                                // ── Remember / Forgot row ─────────────
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    GestureDetector(
                                      onTap: () => setState(() => _rememberMe = !_rememberMe),
                                      child: Row(
                                        children: [
                                          AnimatedContainer(
                                            duration: const Duration(milliseconds: 200),
                                            width: 18,
                                            height: 18,
                                            decoration: BoxDecoration(
                                              color: _rememberMe ? AppColors.accent : Colors.transparent,
                                              borderRadius: BorderRadius.circular(4),
                                              border: Border.all(
                                                color: _rememberMe ? AppColors.accent : AppColors.border2,
                                                width: 1.5,
                                              ),
                                            ),
                                            child: _rememberMe
                                                ? const Icon(Icons.check_rounded, color: Colors.white, size: 13)
                                                : null,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Remember me',
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: AppColors.textSecondary,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: _showResetPasswordDialog,
                                      child: Text(
                                        'Forgot password?',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: AppColors.accent,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 28),

                                // ── Sign In Button ────────────────────
                                SizedBox(
                                  width: double.infinity,
                                  height: 50,
                                  child: ElevatedButton(
                                    onPressed: _isLoading ? null : _signIn,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.accent,
                                      foregroundColor: Colors.white,
                                      disabledBackgroundColor: AppColors.accent.withValues(alpha: 0.6),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      elevation: 0,
                                    ),
                                    child: _isLoading
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2.5,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Text(
                                            'Sign in',
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w600,
                                              letterSpacing: -0.2,
                                            ),
                                          ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // ── About link ──────────────────────────────────
                      FadeTransition(
                        opacity: _fadeAt(0.25, 0.8),
                        child: Center(
                          child: GestureDetector(
                            onTap: _openIntro,
                            child: Text(
                              'About this system',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.textTertiary,
                                decoration: TextDecoration.underline,
                                decorationColor: AppColors.textTertiary,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),

                      // ── Footer ──────────────────────────────────────
                      FadeTransition(
                        opacity: _fadeAt(0.35, 1.0),
                        child: Column(
                          children: [
                            Container(
                              width: 32,
                              height: 3,
                              decoration: BoxDecoration(
                                color: AppColors.accent.withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Developed by Salah \u00a9 2026',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textTertiary,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            if (version.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Version $version (Build $buildNumber)',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textTertiary,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                            if (AppConfig.buildDate.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                'Build: ${AppConfig.buildDate}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textTertiary,
                                ),
                                textAlign: TextAlign.center,
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
          ),
        ],
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
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimary,
        letterSpacing: -0.1,
      ),
    );
  }
}
