import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../config.dart';
import '../services/webauthn_service.dart';

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
  bool _isFaceIdLoading = false;
  bool _faceIdRegistered = false;
  bool _showEnableFaceId = false;

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
      _checkFaceIdRegistered(savedEmail);
    }
  }

  Future<void> _checkFaceIdRegistered(String email) async {
    if (email.isEmpty || !kIsWeb) return;
    try {
      final registered = await WebAuthnService.isRegistered(email);
      if (mounted) setState(() => _faceIdRegistered = registered);
    } catch (_) {}
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
      if (kIsWeb && mounted) {
        final registered = await WebAuthnService.isRegistered(email);
        if (!registered && mounted) setState(() => _showEnableFaceId = true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showSnack(_friendlyError(e.toString()), isError: true);
    }
  }

  Future<void> _signInWithFaceId() async {
    final email = emailController.text.trim();
    if (email.isEmpty) { _showSnack('Enter your email first', isError: true); return; }
    setState(() => _isFaceIdLoading = true);
    try {
      final token = await WebAuthnService.authenticate(email);
      await supabase.auth.verifyOTP(email: email, token: token, type: OtpType.magiclink);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isFaceIdLoading = false);
      final msg = e.toString();
      if (msg.contains('No Face ID') || msg.contains('404')) {
        setState(() { _faceIdRegistered = false; _showEnableFaceId = true; });
        _showSnack('Face ID not set up yet — enable it below');
      } else {
        _showSnack(_friendlyFaceIdError(msg), isError: true);
      }
    }
  }

  Future<void> _enableFaceId() async {
    final email = emailController.text.trim();
    if (email.isEmpty) { _showSnack('Enter your email first', isError: true); return; }
    setState(() => _isFaceIdLoading = true);
    try {
      await WebAuthnService.register(email: email, deviceName: 'iPhone / Browser');
      if (!mounted) return;
      setState(() { _faceIdRegistered = true; _showEnableFaceId = false; _isFaceIdLoading = false; });
      _showSnack('Face ID enabled! You can now sign in with Face ID.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _isFaceIdLoading = false);
      _showSnack(_friendlyFaceIdError(e.toString()), isError: true);
    }
  }

  String _friendlyError(String e) {
    if (e.contains('Invalid login')) return 'Incorrect email or password';
    if (e.contains('Email not confirmed')) return 'Please confirm your email first';
    return 'Sign in failed. Please try again.';
  }

  String _friendlyFaceIdError(String e) {
    if (e.contains('NotAllowedError') || e.contains('cancelled')) return 'Face ID was cancelled';
    if (e.contains('NotSupportedError')) return 'Face ID is not supported on this device';
    if (e.contains('timed out')) return 'Face ID timed out — try again';
    return 'Face ID failed. Try signing in with your password.';
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
                  const Center(child: Text('Work Order', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: AppColors.textPrimary, letterSpacing: -0.4))),
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
                    onChanged: (v) => _checkFaceIdRegistered(v.trim()),
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
                      hintText: '••••••••',
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

                  // Sign in button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _signIn,
                      child: _isLoading
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Sign in'),
                    ),
                  ),

                  // Face ID sign in button (only on web, only if registered)
                  if (kIsWeb && _faceIdRegistered) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _isFaceIdLoading ? null : _signInWithFaceId,
                        icon: _isFaceIdLoading
                            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.5))
                            : const Icon(Icons.face_retouching_natural_rounded, size: 18),
                        label: Text(_isFaceIdLoading ? 'Verifying…' : 'Sign in with Face ID'),
                      ),
                    ),
                  ],

                  // Enable Face ID banner (shown after successful password login)
                  if (kIsWeb && _showEnableFaceId) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.accentBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.accent.withOpacity(0.3), width: 0.5),
                      ),
                      child: Row(children: [
                        const Icon(Icons.face_retouching_natural_rounded, size: 22, color: AppColors.accent),
                        const SizedBox(width: 10),
                        const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Enable Face ID', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.accent)),
                          Text('Sign in faster next time', style: TextStyle(fontSize: 11, color: AppColors.accent)),
                        ])),
                        GestureDetector(
                          onTap: _isFaceIdLoading ? null : _enableFaceId,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(8)),
                            child: _isFaceIdLoading
                                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white))
                                : const Text('Enable', style: TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w500)),
                          ),
                        ),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () => setState(() => _showEnableFaceId = false),
                          child: const Icon(Icons.close_rounded, size: 16, color: AppColors.accent),
                        ),
                      ]),
                    ),
                  ],

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
