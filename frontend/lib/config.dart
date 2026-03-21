class AppConfig {
  static final bool _isLocalhost = Uri.base.host == 'localhost' || Uri.base.host == '127.0.0.1';

  static final String baseUrl = _isLocalhost
      ? 'http://100.85.73.37:8000/api'
      : 'https://zorin.taila92fe8.ts.net/api';

  static final String downloadUrl = _isLocalhost
      ? 'http://100.85.73.37:8000'
      : 'https://zorin.taila92fe8.ts.net';

  static const String buildDate =
      String.fromEnvironment('BUILD_DATE', defaultValue: '16 Mar 2026');
}