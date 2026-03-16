// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

class PlatformUA {
  static bool get isIos {
    final ua = html.window.navigator.userAgent.toLowerCase();
    return ua.contains('iphone') ||
        ua.contains('ipad') ||
        ua.contains('ipod');
  }
}
