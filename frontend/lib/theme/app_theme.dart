import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_transitions.dart';

class AppShadows {
  static List<BoxShadow> get cardLight => [
        BoxShadow(
          color: const Color(0xFF1A1915).withValues(alpha: 0.04),
          blurRadius: 8,
          offset: const Offset(0, 2),
          spreadRadius: 0,
        ),
      ];

  static List<BoxShadow> get cardLightElevated => [
        BoxShadow(
          color: const Color(0xFF1A1915).withValues(alpha: 0.06),
          blurRadius: 12,
          offset: const Offset(0, 4),
          spreadRadius: 0,
        ),
      ];

  static List<BoxShadow> get cardDark => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.2),
          blurRadius: 12,
          offset: const Offset(0, 4),
          spreadRadius: 0,
        ),
      ];

  static List<BoxShadow> get cardDarkElevated => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.3),
          blurRadius: 16,
          offset: const Offset(0, 6),
          spreadRadius: 0,
        ),
      ];

  static List<BoxShadow> get fabLight => [
        BoxShadow(
          color: const Color(0xFFCC785C).withValues(alpha: 0.2),
          blurRadius: 12,
          offset: const Offset(0, 4),
          spreadRadius: 0,
        ),
        BoxShadow(
          color: const Color(0xFF1A1915).withValues(alpha: 0.04),
          blurRadius: 24,
          offset: const Offset(0, 8),
          spreadRadius: 0,
        ),
      ];

  static List<BoxShadow> get fabDark => [
        BoxShadow(
          color: const Color(0xFFCC785C).withValues(alpha: 0.3),
          blurRadius: 12,
          offset: const Offset(0, 4),
          spreadRadius: 0,
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.4),
          blurRadius: 24,
          offset: const Offset(0, 8),
          spreadRadius: 0,
        ),
      ];

  static List<BoxShadow> get dialogLight => [
        BoxShadow(
          color: const Color(0xFF1A1915).withValues(alpha: 0.12),
          blurRadius: 32,
          offset: const Offset(0, 12),
          spreadRadius: -8,
        ),
      ];

  static List<BoxShadow> get dialogDark => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.5),
          blurRadius: 32,
          offset: const Offset(0, 16),
          spreadRadius: -8,
        ),
      ];

  static List<BoxShadow> get inputFocusLight => [
        BoxShadow(
          color: const Color(0xFFCC785C).withValues(alpha: 0.15),
          blurRadius: 8,
          offset: const Offset(0, 2),
          spreadRadius: 0,
        ),
      ];

  static List<BoxShadow> get inputFocusDark => [
        BoxShadow(
          color: const Color(0xFFCC785C).withValues(alpha: 0.3),
          blurRadius: 12,
          offset: const Offset(0, 2),
          spreadRadius: 0,
        ),
      ];

  static List<BoxShadow> card(Brightness brightness, {bool elevated = false}) =>
      brightness == Brightness.light
          ? (elevated ? cardLightElevated : cardLight)
          : (elevated ? cardDarkElevated : cardDark);

  static List<BoxShadow> fab(Brightness brightness) =>
      brightness == Brightness.light ? fabLight : fabDark;

  static List<BoxShadow> dialog(Brightness brightness) =>
      brightness == Brightness.light ? dialogLight : dialogDark;

  static List<BoxShadow> inputFocus(Brightness brightness) =>
      brightness == Brightness.light ? inputFocusLight : inputFocusDark;
}

class AppColors {
  // ── Mode flag ──────────────────────────────────────────────────────────────
  static bool _dark = false;
  static void setDark(bool v) { _dark = v; }
  static bool get isDark => _dark;

  // ── Backgrounds ────────────────────────────────────────────────────────────
  static Color get bgPrimary  => _dark ? const Color(0xFF1A1917) : const Color(0xFFFAF9F7);
  static Color get bgSurface  => _dark ? const Color(0xFF212120) : const Color(0xFFFFFFFF);
  static Color get bgSurface2 => _dark ? const Color(0xFF2A2A28) : const Color(0xFFF5F4F0);
  static Color get bgSurface3 => _dark ? const Color(0xFF343430) : const Color(0xFFECEBE6);

  // ── Text ───────────────────────────────────────────────────────────────────
  static Color get textPrimary   => _dark ? const Color(0xFFEDEDEA) : const Color(0xFF1A1915);
  static Color get textSecondary => _dark ? const Color(0xFF9B9A96) : const Color(0xFF5C5650);
  static Color get textTertiary  => _dark ? const Color(0xFF7A7774) : const Color(0xFF756F68);

  // ── Accent (terracotta — unchanged across modes) ──────────────────────────
  static const Color accent = Color(0xFFCC785C);
  static Color get accentBg => _dark ? const Color(0xFF2C1F1A) : const Color(0xFFF5EBE6);

  // ── Borders ────────────────────────────────────────────────────────────────
  static Color get border  => _dark ? const Color(0x12FFFFFF) : const Color(0x14000000);
  static Color get border2 => _dark ? const Color(0x1CFFFFFF) : const Color(0x1F000000);

  // ── Status ─────────────────────────────────────────────────────────────────
  static Color get pendingText    => _dark ? const Color(0xFFFDE68A) : const Color(0xFF92400E);
  static Color get pendingBg      => _dark ? const Color(0xFF78350F) : const Color(0xFFFDE68A);
  static Color get inProgressText => _dark ? const Color(0xFFBFDBFE) : const Color(0xFF1E40AF);
  static Color get inProgressBg   => _dark ? const Color(0xFF1E3A8A) : const Color(0xFFBFDBFE);
  static Color get closedText     => _dark ? const Color(0xFFDCFCE7) : const Color(0xFF15803D);
  static Color get closedBg       => _dark ? const Color(0xFF14532D) : const Color(0xFFDCFCE7);

  // ── Danger ─────────────────────────────────────────────────────────────────
  static const Color dangerText   = Color(0xFFDC2626);
  static Color get dangerBg     => _dark ? const Color(0xFF2A0A0A) : const Color(0xFFFEF2F2);
  static Color get dangerBorder => _dark ? const Color(0xFF7F1D1D) : const Color(0xFFFECACA);
}

class AppTheme {
  static TextTheme _buildTextTheme(String fontFamily) {
    final base = switch (fontFamily) {
      'DM Sans'  => GoogleFonts.dmSansTextTheme(),
      'Roboto'   => GoogleFonts.robotoTextTheme(),
      'Poppins'  => GoogleFonts.poppinsTextTheme(),
      'Lato'     => GoogleFonts.latoTextTheme(),
      'Nunito'   => GoogleFonts.nunitoTextTheme(),
      'Inter'    => GoogleFonts.interTextTheme(),
      _          => GoogleFonts.interTextTheme(),
    };
    return base;
  }

  static ThemeData light([Color accent = AppColors.accent, String fontFamily = 'DM Sans']) =>
      _build(Brightness.light, accent, fontFamily);

  static ThemeData dark([Color accent = AppColors.accent, String fontFamily = 'DM Sans']) =>
      _build(Brightness.dark, accent, fontFamily);

  static ThemeData _build(Brightness brightness, Color accent, String fontFamily) {
    final isDark = brightness == Brightness.dark;
    final base = _buildTextTheme(fontFamily);

    final bgPrimary   = isDark ? const Color(0xFF1A1917) : const Color(0xFFFAF9F7);
    final bgSurface   = isDark ? const Color(0xFF212120) : const Color(0xFFFFFFFF);
    final bgSurface2  = isDark ? const Color(0xFF2A2A28) : const Color(0xFFF5F4F0);
    final textPrimary = isDark ? const Color(0xFFEDEDEA) : const Color(0xFF1A1915);
    final textSec     = isDark ? const Color(0xFF9B9A96) : const Color(0xFF5C5650);
    final textTert    = isDark ? const Color(0xFF7A7774) : const Color(0xFF756F68);
    final border      = isDark ? const Color(0x12FFFFFF) : const Color(0x14000000);
    final border2     = isDark ? const Color(0x1CFFFFFF) : const Color(0x1F000000);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: bgPrimary,
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        brightness: brightness,
        surface: bgSurface,
      ),
      focusColor: accent.withValues(alpha: 0.12),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ClaudeTransitionsBuilder(),
          TargetPlatform.iOS: ClaudeTransitionsBuilder(),
          TargetPlatform.windows: ClaudeTransitionsBuilder(),
          TargetPlatform.macOS: ClaudeTransitionsBuilder(),
          TargetPlatform.linux: ClaudeTransitionsBuilder(),
        },
      ),
      textTheme: base.copyWith(
        displayLarge: base.displayLarge?.copyWith(fontSize: 28, fontWeight: FontWeight.w600, color: textPrimary, letterSpacing: -0.5),
        titleLarge:   base.titleLarge?.copyWith(fontSize: 20, fontWeight: FontWeight.w600, color: textPrimary, letterSpacing: -0.3),
        titleMedium:  base.titleMedium?.copyWith(fontSize: 16, fontWeight: FontWeight.w600, color: textPrimary),
        bodyLarge:    base.bodyLarge?.copyWith(fontSize: 14, fontWeight: FontWeight.w400, color: textPrimary, height: 1.5),
        bodyMedium:   base.bodyMedium?.copyWith(fontSize: 13, fontWeight: FontWeight.w400, color: textSec, height: 1.5),
        bodySmall:    base.bodySmall?.copyWith(fontSize: 11, fontWeight: FontWeight.w400, color: textTert),
        labelSmall:   base.labelSmall?.copyWith(fontSize: 10, fontWeight: FontWeight.w500, color: textTert, letterSpacing: 0.06),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: bgSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: border, width: 0.5),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: bgSurface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: border2, width: 0.5)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: border2, width: 0.5)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: accent, width: 2)),
        hintStyle: TextStyle(color: textTert, fontSize: 13),
        labelStyle: TextStyle(color: textSec, fontSize: 11),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          side: BorderSide(color: border2, width: 0.5),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: bgSurface2,
        selectedColor: textPrimary,
        labelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: textSec),
        side: BorderSide(color: border2, width: 0.5),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: bgSurface,
        indicatorColor: accent.withValues(alpha: 0.12),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return IconThemeData(color: accent, size: 22);
          return IconThemeData(color: textTert, size: 22);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: accent);
          return TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: textTert);
        }),
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        height: 64,
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 0.5, space: 0),
      appBarTheme: AppBarTheme(
        backgroundColor: bgSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: textPrimary,
        titleTextStyle: GoogleFonts.getFont(fontFamily, textStyle: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textPrimary)),
        iconTheme: IconThemeData(color: textSec, size: 20),
        surfaceTintColor: Colors.transparent,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: bgSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}
