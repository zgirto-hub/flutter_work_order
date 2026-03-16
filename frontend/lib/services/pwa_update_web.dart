import 'dart:js_interop';

@JS('applyPWAUpdate')
external void _jsApplyPWAUpdate();

void applyPWAUpdate() => _jsApplyPWAUpdate();
