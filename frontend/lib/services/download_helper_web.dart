// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

bool get isIosWeb {
  final ua = html.window.navigator.userAgent.toLowerCase();
  return ua.contains('iphone') || ua.contains('ipad') || ua.contains('ipod');
}

Future<void> downloadFile(String url, String fileName) async {
  // iOS PWA runs in a WKWebView that cannot open new tabs, so downloads are
  // handled by hiding the button entirely — see document_details_screen.dart.
  // This path should not be reached on iOS web.
  (html.AnchorElement(href: url)
    ..setAttribute('download', fileName)
    ..click());
}
