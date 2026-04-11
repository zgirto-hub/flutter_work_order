import 'package:web/web.dart' as web;

bool canUseNativeShareControl() {
  final ua = web.window.navigator.userAgent.toLowerCase();
  final isIos =
      ua.contains('iphone') || ua.contains('ipad') || ua.contains('ipod');
  final isAndroid = ua.contains('android') && ua.contains('mobile');
  return isIos || isAndroid;
}
