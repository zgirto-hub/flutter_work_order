import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeController extends ChangeNotifier {
  Color _color = Colors.blue;
  double _fontScale = 1.0;

  Color get color => _color;
  double get fontScale => _fontScale;

  ThemeController() {
    _loadPrefs();
  }

  Future<void> changeColor(Color newColor) async {
    _color = newColor;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    prefs.setInt('theme_color', newColor.value);
  }

  Future<void> setFontScale(double scale) async {
    _fontScale = scale;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    prefs.setDouble('font_scale', scale);
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final savedColor = prefs.getInt('theme_color');
    final savedScale = prefs.getDouble('font_scale');
    if (savedColor != null) _color = Color(savedColor);
    if (savedScale != null) _fontScale = savedScale;
    notifyListeners();
  }
}
