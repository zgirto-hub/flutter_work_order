import 'dart:js_interop';

@JS('applyPWAUpdate')
external void _jsApplyPWAUpdate();

@JS('_swUpdateReady')
external bool get _jsSwUpdateReady;

void applyPWAUpdate() => _jsApplyPWAUpdate();

bool checkSwUpdate() {
  try {
    return _jsSwUpdateReady;
  } catch (_) {
    return false;
  }
}
