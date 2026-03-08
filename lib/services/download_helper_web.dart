import 'dart:html' as html;

Future<void> downloadFile(String url, String fileName) async {
  final anchor = html.AnchorElement(href: url)
    ..setAttribute("download", fileName)
    ..click();
}

