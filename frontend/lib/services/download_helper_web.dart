import 'dart:html' as html;

Future<void> downloadFile(String url, String fileName) async {
  // iOS Safari (PWA and browser) ignores the `download` attribute.
  // Open in a new tab so the user gets the native preview / share sheet.
  final ua = html.window.navigator.userAgent.toLowerCase();
  final isIos = ua.contains('iphone') || ua.contains('ipad') || ua.contains('ipod');

  if (isIos) {
    html.window.open(url, '_blank');
    return;
  }

  // All other platforms: trigger a normal browser download.
  final anchor = html.AnchorElement(href: url)
    ..setAttribute('download', fileName)
    ..click();
}

