import 'dart:js_interop';

@JS('applyPWAUpdate')
external void _jsApplyPWAUpdate();

@JS('checkForAppUpdate')
external JSPromise<JSString> _jsCheckForAppUpdate();

@JS('registerUpdateCallback')
external void _jsRegisterUpdateCallback(JSFunction callback);

/// Possible results of a version update check.
enum UpdateStatus { available, upToDate, error }

/// Triggers the reload overlay and reloads the page.
void applyUpdate() => _jsApplyPWAUpdate();

/// Checks version.json for a new release.
/// Returns [UpdateStatus.available], [UpdateStatus.upToDate], or [UpdateStatus.error].
Future<UpdateStatus> checkForUpdate() async {
  try {
    final result = await _jsCheckForAppUpdate().toDart;
    final value = result.toDart;
    switch (value) {
      case 'available':
        return UpdateStatus.available;
      case 'upToDate':
        return UpdateStatus.upToDate;
      default:
        return UpdateStatus.error;
    }
  } catch (_) {
    return UpdateStatus.error;
  }
}

/// Registers a callback invoked when [checkForAppUpdate] detects a version mismatch.
void registerUpdateCallback(void Function() callback) {
  try {
    _jsRegisterUpdateCallback(callback.toJS);
  } catch (_) {}
}
