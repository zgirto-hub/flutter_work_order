// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

Future<void> downloadFile(String url, String fileName) async {
  final ua = html.window.navigator.userAgent.toLowerCase();
  final isIos = ua.contains('iphone') || ua.contains('ipad') || ua.contains('ipod');

  if (isIos) {
    // On iOS PWA/Safari: open the file in a new tab so the user gets the
    // native QuickLook preview with a "Done" button to return.
    // We use a temporary <a target="_blank"> because window.open() is
    // blocked in PWA standalone mode on iOS.
    final anchor = html.AnchorElement(href: url)
      ..setAttribute('target', '_blank')
      ..setAttribute('rel', 'noopener noreferrer');
    html.document.body?.append(anchor);
    anchor.click();
    // Small delay before removal to ensure the click registers
    await Future.delayed(const Duration(milliseconds: 100));
    anchor.remove();
    return;
  }

  // All other platforms: trigger a normal browser download.
  (html.AnchorElement(href: url)
    ..setAttribute('download', fileName)
    ..click());
}
