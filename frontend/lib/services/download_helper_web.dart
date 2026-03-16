import 'dart:html' as html;

Future<void> downloadFile(String url, String fileName) async {
  // iOS Safari (PWA and browser) ignores the `download` attribute.
  // Open in a new tab so the user gets the native preview / share sheet.
  final ua = html.window.navigator.userAgent.toLowerCase();
  final isIos = ua.contains('iphone') || ua.contains('ipad') || ua.contains('ipod');

  if (isIos) {
    // PWA standalone mode blocks window.open(). Navigate the current window
    // to the file URL — iOS intercepts it with a native QuickLook preview.
    // The user taps Done to return to the PWA.
    html.window.location.href = url;
    return;
  }

  // All other platforms: trigger a normal browser download.
  (html.AnchorElement(href: url)
    ..setAttribute('download', fileName)
    ..click());
}

