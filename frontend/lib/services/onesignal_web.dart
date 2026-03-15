import 'dart:js_interop';

@JS('oneSignalSubscribe')
external JSPromise<JSBoolean> _subscribe(String email, String role);

@JS('oneSignalUnsubscribe')
external JSPromise<JSAny?> _unsubscribe();

@JS('oneSignalRequestPermission')
external JSPromise<JSAny?> _requestPermission();

@JS('eval')
external JSString _evalString(String code);

Future<void> subscribeToOneSignal(String email, String role) async {
  await _subscribe(email, role).toDart;
}

Future<void> unsubscribeFromOneSignal() async {
  await _unsubscribe().toDart;
}

Future<bool> requestOneSignalPermission() async {
  try {
    await _requestPermission().toDart;
    return true;
  } catch (e) {
    return false;
  }
}

bool isNotificationPermissionGranted() {
  try {
    return _evalString('Notification.permission').toDart == 'granted';
  } catch (_) {
    return false;
  }
}
