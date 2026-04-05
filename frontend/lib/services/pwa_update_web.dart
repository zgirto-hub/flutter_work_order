import 'dart:js_interop';

@JS('applyPWAUpdate')
external void _jsApplyPWAUpdate();

@JS('_swUpdateReady')
external bool get _jsSwUpdateReady;

@JS('_checkForSwUpdate')
external void _jsCheckForSwUpdate();

@JS('_registerSwUpdateCallback')
external void _jsRegisterSwUpdateCallback(JSFunction callback);

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

// New: Register callback for immediate update detection
void registerSwUpdateCallback(void Function() callback) {
  try {
    _jsRegisterSwUpdateCallback(callback.toJS);
  } catch (_) {}
}
