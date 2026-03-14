class AppConfig {
  // abood-old-pc : Tailscale ip
 /* static const String baseUrl = "http://100.85.73.37:8000/api";
  static const String downloadUrl = "http://100.85.73.37:8000";
*/
static const String baseUrl = "https://zorin.taila92fe8.ts.net/api";
  static const String downloadUrl = "https://zorin.taila92fe8.ts.net";
  static const String buildDate =
      String.fromEnvironment('BUILD_DATE', defaultValue: '14 Mar 2026');
}