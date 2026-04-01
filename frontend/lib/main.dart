import 'dart:math' show cos, sin, pi;

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/main_screen.dart';
import 'screens/login_screen.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  runApp(const _BootstrapApp());
}

// ── Bootstrap: shows splash while initialising services ─────────────────────

class _BootstrapApp extends StatefulWidget {
  const _BootstrapApp();

  @override
  State<_BootstrapApp> createState() => _BootstrapAppState();
}

class _BootstrapAppState extends State<_BootstrapApp> {
  ThemeController? _themeController;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await dotenv.load(fileName: '.env');

    // Run Supabase init and theme prefs loading in parallel.
    final results = await Future.wait([
      Supabase.initialize(
        url: dotenv.env['SUPABASE_URL']!,
        anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
      ),
      ThemeController.create(),
    ]);

    if (!mounted) return;
    setState(() => _themeController = results[1] as ThemeController);
  }

  @override
  Widget build(BuildContext context) {
    final controller = _themeController;
    if (controller == null) {
      // Services still loading — show branded splash immediately.
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: _SplashScreen(),
      );
    }
    return MyApp(themeController: controller);
  }
}

// ── Main app (shown after init completes) ───────────────────────────────────

class MyApp extends StatelessWidget {
  final ThemeController themeController;
  const MyApp({super.key, required this.themeController});

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
            theme: AppTheme.light(themeController.color, themeController.fontFamily),
            darkTheme: AppTheme.dark(themeController.color, themeController.fontFamily),
            themeMode: themeController.mode,
            home: AuthWrapper(themeController: themeController),
          ),
        );
      },
    );
  }
}

// ── Splash screen (ticket design) ───────────────────────────────────────────

class _SplashScreen extends StatefulWidget {
  const _SplashScreen();

  @override
  State<_SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<_SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<double> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<double>(begin: 20, end: 0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic),
    );
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF9F7),
      body: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, child) => FadeTransition(
          opacity: _fade,
          child: Transform.translate(
            offset: Offset(0, _slide.value),
            child: child,
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: const Padding(
              padding: EdgeInsets.all(32),
              child: _TicketCard(),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Ticket card ──────────────────────────────────────────────────────────────

class _TicketCard extends StatelessWidget {
  const _TicketCard();

  static const _terracotta = Color(0xFFCC785C);
  static const _cream      = Color(0xFFFAF9F7);
  static const _white      = Color(0xFFFFFFFF);
  static const _textDark   = Color(0xFF1A1915);
  static const _textLight  = Color(0xFF9B9A96);
  static const _divider    = Color(0xFFE8E6E0);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0x35CC785C)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 48,
            offset: Offset(0, 12),
          ),
          BoxShadow(
            color: Color(0x09CC785C),
            blurRadius: 24,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildStub(left: true),
              _buildDash(),
              Expanded(child: _buildContent()),
              _buildDash(),
              _buildStub(left: false),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStub({required bool left}) {
    return Container(
      width: 28,
      color: _cream,
      child: RotatedBox(
        quarterTurns: left ? 1 : 3,
        child: Center(
          child: Text(
            left ? '0000001 · CLICK HERE' : 'CLICK HERE · 0000001',
            style: const TextStyle(
              fontSize: 6.5,
              fontWeight: FontWeight.w800,
              color: _textLight,
              letterSpacing: 1.6,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDash() => SizedBox(
    width: 1,
    child: CustomPaint(painter: _DashPainter(_divider)),
  );

  Widget _buildContent() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Top terracotta stripe
        Container(height: 3.5, color: _terracotta),

        // ── Top label
        _labelRow(flipped: false),

        Container(height: 0.5, color: _divider),

        // ── Main body
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 38, 28, 32),
          child: Column(
            children: [
              // Icon: terracotta rounded square with drawn asterisk
              Container(
                width: 82,
                height: 82,
                decoration: BoxDecoration(
                  color: _terracotta,
                  borderRadius: BorderRadius.circular(21),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x32CC785C),
                      blurRadius: 22,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: CustomPaint(
                  painter: _AsteriskPainter(_white),
                ),
              ),

              const SizedBox(height: 22),

              // Title
              const Text(
                'Work Order',
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  color: _textDark,
                  letterSpacing: -1.1,
                ),
              ),

              const SizedBox(height: 7),

              // Subtitle
              const Text(
                'Loading, please wait...',
                style: TextStyle(
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                  color: _terracotta,
                  letterSpacing: 0.1,
                ),
              ),

              const SizedBox(height: 28),

              // Progress bar
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: const LinearProgressIndicator(
                  value: null,
                  backgroundColor: _divider,
                  valueColor: AlwaysStoppedAnimation(_terracotta),
                  minHeight: 2.5,
                ),
              ),
            ],
          ),
        ),

        Container(height: 0.5, color: _divider),

        // ── Bottom label (upside down — classic ticket style)
        _labelRow(flipped: true),

        // ── Bottom terracotta stripe
        Container(height: 3.5, color: _terracotta),
      ],
    );
  }

  Widget _labelRow({required bool flipped}) {
    Widget row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 7),
      child: Row(
        children: [
          Text('ADMIT ONE', style: _labelStyle()),
          const Spacer(),
          Text('•', style: _labelStyle()),
          const Spacer(),
          Text('VALID FOR: WORK ORDER SYSTEM', style: _labelStyle()),
        ],
      ),
    );
    if (flipped) row = Transform.scale(scaleY: -1, child: row);
    return row;
  }

  static TextStyle _labelStyle() => const TextStyle(
    fontSize: 7,
    fontWeight: FontWeight.w800,
    color: _textLight,
    letterSpacing: 1.5,
  );
}

// ── Painters ─────────────────────────────────────────────────────────────────

class _DashPainter extends CustomPainter {
  final Color color;
  const _DashPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1;
    const d = 5.0, g = 4.0;
    for (double y = 0; y < size.height; y += d + g) {
      canvas.drawLine(Offset(0.5, y), Offset(0.5, y + d), p);
    }
  }

  @override
  bool shouldRepaint(_DashPainter o) => o.color != color;
}

class _AsteriskPainter extends CustomPainter {
  final Color color;
  const _AsteriskPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final spoke = Paint()
      ..color = color
      ..strokeWidth = size.width * 0.088
      ..strokeCap = StrokeCap.round;

    final dot = Paint()..color = color;

    final cx = size.width / 2;
    final cy = size.height / 2;
    final r  = size.width * 0.31;

    for (int i = 0; i < 6; i++) {
      final a = (i * 60 - 90) * pi / 180;
      canvas.drawLine(
        Offset(cx, cy),
        Offset(cx + r * cos(a), cy + r * sin(a)),
        spoke,
      );
    }
    canvas.drawCircle(Offset(cx, cy), size.width * 0.052, dot);
  }

  @override
  bool shouldRepaint(_AsteriskPainter o) => o.color != color;
}

// ── Auth wrapper ──────────────────────────────────────────────────────────────

class AuthWrapper extends StatelessWidget {
  final ThemeController themeController;
  const AuthWrapper({super.key, required this.themeController});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        // Full-screen ticket splash while stream initialises
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _SplashScreen();
        }

        final session = snapshot.data?.session;
        final child = session == null
            ? const LoginScreen(key: ValueKey('login'))
            : MainScreen(key: const ValueKey('main'), themeController: themeController);

        // 620px card shell for login / main app
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
                    color: Colors.black.withValues(alpha: 0.06),
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
                    child: child,
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
