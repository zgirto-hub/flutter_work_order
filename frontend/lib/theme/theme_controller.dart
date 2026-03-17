import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_theme.dart';

const List<String> kAvailableFonts = ['Inter', 'DM Sans', 'Roboto', 'Poppins', 'Lato', 'Nunito'];

class ThemeController extends ChangeNotifier {
  Color _color = Colors.blue;
  double _fontScale = 1.0;
  String _fontFamily = 'Inter';
  ThemeMode _mode = ThemeMode.light;

  Color get color => _color;
  double get fontScale => _fontScale;
  String get fontFamily => _fontFamily;
  ThemeMode get mode => _mode;

  ThemeController() {
    _loadPrefs();
  }

  Future<void> changeColor(Color newColor) async {
    _color = newColor;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    prefs.setInt('theme_color', newColor.toARGB32());
  }

  Future<void> setFontScale(double scale) async {
    _fontScale = scale;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    prefs.setDouble('font_scale', scale);
  }

  Future<void> setFontFamily(String family) async {
    _fontFamily = family;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('font_family', family);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _mode = mode;
    AppColors.setDark(mode == ThemeMode.dark);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('theme_mode', mode.name);
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final savedColor = prefs.getInt('theme_color');
    final savedScale = prefs.getDouble('font_scale');
    final savedFont  = prefs.getString('font_family');
    final savedMode  = prefs.getString('theme_mode');
    if (savedColor != null) _color = Color(savedColor);
    if (savedScale != null) _fontScale = savedScale;
    if (savedFont  != null) _fontFamily = savedFont;
    if (savedMode  != null) {
      _mode = ThemeMode.values.firstWhere(
        (m) => m.name == savedMode,
        orElse: () => ThemeMode.light,
      );
    }
    AppColors.setDark(_mode == ThemeMode.dark);
    notifyListeners();
  }
}
