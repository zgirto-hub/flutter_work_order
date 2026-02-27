import 'package:flutter/material.dart';

class ThemeController extends ChangeNotifier {
  Color _primaryColor = const Color(0xFF2563EB);

  Color get primaryColor => _primaryColor;

  void changeColor(Color newColor) {
    _primaryColor = newColor;
    notifyListeners();
  }
}
