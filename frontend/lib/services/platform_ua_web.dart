import 'package:web/web.dart' as web;

class PlatformUA {
  static bool get isIos {
    final ua = web.window.navigator.userAgent.toLowerCase();
    return ua.contains('iphone') ||
        ua.contains('ipad') ||
        ua.contains('ipod');
  }
}
