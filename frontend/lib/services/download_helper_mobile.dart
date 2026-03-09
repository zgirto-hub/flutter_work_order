import 'package:url_launcher/url_launcher.dart';

Future<void> downloadFile(String url, String fileName) async {
  final uri = Uri.parse(url);

  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } else {
    throw "Could not open download link";
  }
}