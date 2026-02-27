import 'package:flutter/material.dart';

class ThemeController extends ChangeNotifier {
  Color _primaryColor = Colors.blue;

  Color get primaryColor => _primaryColor;

  void changeColor(Color newColor) {
    _primaryColor = newColor;
    notifyListeners();
  }
}
