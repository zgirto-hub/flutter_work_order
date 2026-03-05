class AppConfig {
  // abood-old-pc : Tailscale ip
  static const String baseUrl = "http://100.85.73.37:8000/api";
  static const String downloadUrl = "http://100.85.73.37:8000";

  static const String buildDate =
      String.fromEnvironment('BUILD_DATE', defaultValue: '5 Mar 2026');
}