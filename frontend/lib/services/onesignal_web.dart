import 'dart:js_interop';

@JS('oneSignalSubscribe')
external JSPromise<JSBoolean> _subscribe(String email, String role);

@JS('oneSignalUnsubscribe')
external JSPromise<JSAny?> _unsubscribe();

@JS('oneSignalRequestPermission')
external JSPromise<JSBoolean> _requestPermission();

Future<void> subscribeToOneSignal(String email, String role) async {
  await _subscribe(email, role).toDart;
}

Future<void> unsubscribeFromOneSignal() async {
  await _unsubscribe().toDart;
}

Future<bool> requestOneSignalPermission() async {
  final result = await _requestPermission().toDart;
  return result.toDart;
}
