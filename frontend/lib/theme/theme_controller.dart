import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeController extends ChangeNotifier {
  Color _color = Colors.blue;

  Color get color => _color;

  ThemeController() {
    _loadTheme();
  }

  Future<void> changeColor(Color newColor) async {
    _color = newColor;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    prefs.setInt('theme_color', newColor.value);
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();

    final savedColor = prefs.getInt('theme_color');

    if (savedColor != null) {
      _color = Color(savedColor);
      notifyListeners();
    }
  }
}