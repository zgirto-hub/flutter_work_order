import 'package:flutter/foundation.dart' show kIsWeb;
import 'onesignal_web.dart'
    if (dart.library.io) 'onesignal_stub.dart';

class OneSignalService {
  static Future<void> subscribe(String email, String role) async {
    if (!kIsWeb) return;
    await subscribeToOneSignal(email, role);
  }

  static Future<void> unsubscribe() async {
    if (!kIsWeb) return;
    await unsubscribeFromOneSignal();
  }
}
