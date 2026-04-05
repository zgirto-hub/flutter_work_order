import 'dart:js_interop';

@JS('applyPWAUpdate')
external void _jsApplyPWAUpdate();

@JS('_swUpdateReady')
external bool get _jsSwUpdateReady;

@JS('_checkForSwUpdate')
external void _jsCheckForSwUpdate();

void applyPWAUpdate() => _jsApplyPWAUpdate();

bool checkSwUpdate() {
  try {
    return _jsSwUpdateReady;
  } catch (_) {
    return false;
  }
}

void triggerSwUpdateCheck() {
  try {
    _jsCheckForSwUpdate();
  } catch (_) {}
}
