// Web implementation using dart:js_interop (Dart 3.x compatible)
import 'dart:js_interop';
import 'dart:async';

@JS('webauthnIsSupported')
external bool _webauthnIsSupported();

@JS('webauthnIsPlatformSupported')
external JSPromise<JSBoolean> _webauthnIsPlatformSupported();

@JS('webauthnRegister')
external JSPromise<JSString> _webauthnRegister(String optionsJson);

@JS('webauthnAuthenticate')
external JSPromise<JSString> _webauthnAuthenticate(String optionsJson);

Future<bool> checkWebAuthnSupport() async {
  if (!_webauthnIsSupported()) return false;
  try {
    final result = await _webauthnIsPlatformSupported().toDart;
    return result.toDart;
  } catch (_) {
    return false;
  }
}

Future<String> callWebAuthnRegister(String optionsJson) async {
  final result = await _webauthnRegister(optionsJson).toDart;
  return result.toDart;
}

Future<String> callWebAuthnAuthenticate(String optionsJson) async {
  final result = await _webauthnAuthenticate(optionsJson).toDart;
  return result.toDart;
}
