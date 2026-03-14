// Web implementation — calls window.webauthnRegister / window.webauthnAuthenticate
// from webauthn.js via dart:js

// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:js' as js;
import 'dart:async';

Future<bool> checkWebAuthnSupport() async {
  final supported = js.context.callMethod('webauthnIsSupported', []);
  if (supported != true) return false;

  final completer = Completer<bool>();

  js.context.callMethod('webauthnIsPlatformSupported', []).then((result) {
    completer.complete(result == true);
  }).catchError((_) {
    completer.complete(false);
  });

  return completer.future;
}

Future<String> callWebAuthnRegister(String optionsJson) async {
  final completer = Completer<String>();

  final promise = js.context.callMethod('webauthnRegister', [optionsJson]);

  promise.then((result) {
    completer.complete(result.toString());
  }).catchError((error) {
    completer.completeError(Exception(error.toString()));
  });

  return completer.future;
}

Future<String> callWebAuthnAuthenticate(String optionsJson) async {
  final completer = Completer<String>();

  final promise = js.context.callMethod('webauthnAuthenticate', [optionsJson]);

  promise.then((result) {
    completer.complete(result.toString());
  }).catchError((error) {
    completer.completeError(Exception(error.toString()));
  });

  return completer.future;
}
