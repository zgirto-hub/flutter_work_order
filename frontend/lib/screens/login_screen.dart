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
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: AppColors.bgPrimary,
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [

                  // ── Logo + Brand ───────────────────────────────────────
                  FadeTransition(
                    opacity: _fadeAt(0.0, 0.55),
                    child: SlideTransition(
                      position: _slideAt(0.0, 0.55),
                      child: Column(
                        children: [
                          const _AppLogo(),
                          const SizedBox(height: 20),
                          Text(
                            'Work Order',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Workflow Management',
                            style: TextStyle(
                              fontSize: 14,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                          const SizedBox(height: 10),
                          GestureDetector(
                            onTap: _openIntro,
                            child: Text(
                              'About this system',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textTertiary,
                                decoration: TextDecoration.underline,
                                decorationColor: AppColors.textTertiary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 48),

                  // ── Welcome Message ────────────────────────────────────
                  FadeTransition(
                    opacity: _fadeAt(0.1, 0.6),
                    child: SlideTransition(
                      position: _slideAt(0.1, 0.6),
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
                          const SizedBox(height: 6),
                          Text(
                            'Sign in to continue to your workspace',
                            style: TextStyle(
                              fontSize: 14,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // ── Form fields ────────────────────────────────────────
                  FadeTransition(
                    opacity: _fadeAt(0.2, 0.75),
                    child: SlideTransition(
                      position: _slideAt(0.2, 0.75),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _InputLabel(label: 'Email'),
                          const SizedBox(height: 8),
                          TextField(
                            controller: emailController,
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [AutofillHints.email, AutofillHints.username],
                            textInputAction: TextInputAction.next,
                            style: TextStyle(fontSize: 14, color: AppColors.textPrimary),
                            decoration: const InputDecoration(
                              hintText: 'name@company.com',
                              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            ),
                          ),
                          const SizedBox(height: 20),

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
                                        color: _rememberMe ? AppColors.textPrimary : Colors.transparent,
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: _rememberMe ? AppColors.textPrimary : AppColors.border2,
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
                                    color: AppColors.textSecondary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // ── Sign In Button ─────────────────────────────────────
                  FadeTransition(
                    opacity: _fadeAt(0.3, 0.85),
                    child: SlideTransition(
                      position: _slideAt(0.3, 0.85),
                      child: SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _signIn,
                          style: ElevatedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
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
                    ),
                  ),
                  const SizedBox(height: 40),

                  // ── Footer ─────────────────────────────────────────────
                  FadeTransition(
                    opacity: _fadeAt(0.4, 1.0),
                    child: Column(
                      children: [
                        Text(
                          'Developed by Salah © 2026',
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

// ── App Logo ───────────────────────────────────────────────────────────────────
// Stacked document layers with a checkmark — represents work order completion.

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
          colors: [Color(0xFFE89977), Color(0xFFB85E3F)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.15),
          width: 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFCC785C).withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: const Color(0xFFCC785C).withValues(alpha: 0.15),
            blurRadius: 32,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: [
          const CustomPaint(painter: _LogoMarkPainter()),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: 0.12),
                    Colors.transparent,
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.05),
                  ],
                  stops: const [0.0, 0.3, 0.7, 1.0],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LogoMarkPainter extends CustomPainter {
  const _LogoMarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final white90 = Paint()
      ..color = Colors.white.withValues(alpha: 0.92)
      ..style = PaintingStyle.fill;

    final white50 = Paint()
      ..color = Colors.white.withValues(alpha: 0.45)
      ..style = PaintingStyle.fill;

    final white30 = Paint()
      ..color = Colors.white.withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;

    // Back page (offset right + down)
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.28, h * 0.18, w * 0.48, h * 0.58),
        const Radius.circular(3),
      ),
      white30,
    );

    // Middle page (offset slightly)
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.24, h * 0.22, w * 0.48, h * 0.58),
        const Radius.circular(3),
      ),
      white50,
    );

    // Front page with folded corner
    final pageRect = Rect.fromLTWH(w * 0.20, h * 0.16, w * 0.48, h * 0.58);
    final foldSize = w * 0.12;
    final pagePath = Path()
      ..moveTo(pageRect.left, pageRect.top)
      ..lineTo(pageRect.right - foldSize, pageRect.top)
      ..lineTo(pageRect.right, pageRect.top + foldSize)
      ..lineTo(pageRect.right, pageRect.bottom)
      ..lineTo(pageRect.left, pageRect.bottom)
      ..close();
    canvas.drawPath(pagePath, white90);

    // Folded corner triangle
    final foldPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..style = PaintingStyle.fill;
    final foldPath = Path()
      ..moveTo(pageRect.right - foldSize, pageRect.top)
      ..lineTo(pageRect.right - foldSize, pageRect.top + foldSize)
      ..lineTo(pageRect.right, pageRect.top + foldSize)
      ..close();
    canvas.drawPath(foldPath, foldPaint);

    // Checkmark
    final checkPaint = Paint()
      ..color = const Color(0xFFB85E3F)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final cx = pageRect.center.dx;
    final cy = pageRect.center.dy + h * 0.02;
    final checkPath = Path()
      ..moveTo(cx - w * 0.07, cy)
      ..lineTo(cx - w * 0.01, cy + h * 0.07)
      ..lineTo(cx + w * 0.09, cy - h * 0.06);
    canvas.drawPath(checkPath, checkPaint);
  }

  @override
  bool shouldRepaint(_LogoMarkPainter oldDelegate) => false;
}
