class AppConfig {
  static const String baseUrl = String.fromEnvironment(
    'BASE_URL',
    defaultValue: 'https://zorin.taila92fe8.ts.net/api',
  );
  static const String downloadUrl = String.fromEnvironment(
    'DOWNLOAD_URL',
    defaultValue: 'https://zorin.taila92fe8.ts.net',
  );
  static const String buildDate =
      String.fromEnvironment('BUILD_DATE', defaultValue: '16 Mar 2026');
}