import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConfig {
  static final bool _isLocalhost =
      Uri.base.host == 'localhost' || Uri.base.host == '127.0.0.1';

  static final String baseUrl = _isLocalhost
      ? (dotenv.env['API_BASE_URL_LOCAL'] ?? 'http://localhost:8000/api')
      : (dotenv.env['API_BASE_URL_PROD'] ?? '');

  static final String downloadUrl = _isLocalhost
      ? (dotenv.env['DOWNLOAD_URL_LOCAL'] ?? 'http://localhost:8000')
      : (dotenv.env['DOWNLOAD_URL_PROD'] ?? '');

  static const String buildDate =
      String.fromEnvironment('BUILD_DATE', defaultValue: '16 Mar 2026');
}
