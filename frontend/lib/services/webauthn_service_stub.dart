// Mobile stub — WebAuthn is web-only
// These functions are never called on non-web platforms

Future<bool> checkWebAuthnSupport() async => false;

Future<String> callWebAuthnRegister(String optionsJson) async {
  throw UnsupportedError('WebAuthn is only supported on web');
}

Future<String> callWebAuthnAuthenticate(String optionsJson) async {
  throw UnsupportedError('WebAuthn is only supported on web');
}
