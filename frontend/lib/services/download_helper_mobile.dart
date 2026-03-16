import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

// Always false on native mobile — only true on web iOS.
bool get isIosWeb => false;

void openInNewTab(String url) {} // no-op on native

Future<void> downloadFile(String url, String fileName) async {
  // On iOS, launchUrl(externalApplication) leaves the app and breaks back
  // navigation. Download to a temp file and use the share sheet instead.
  if (!kIsWeb && Platform.isIOS) {
    final response = await http
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 60));

    if (response.statusCode != 200) {
      throw 'Server returned ${response.statusCode}';
    }

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(response.bodyBytes);

    await Share.shareXFiles(
      [XFile(file.path)],
      fileNameOverrides: [fileName],
    );
    return;
  }

  // Android / other platforms — open with external app as before.
  final uri = Uri.parse(url);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } else {
    throw 'Could not open download link';
  }
}
