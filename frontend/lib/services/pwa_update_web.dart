import 'dart:js_interop';

@JS('applyPWAUpdate')
external void _jsApplyPWAUpdate();

@JS('checkForAppUpdate')
external JSPromise<JSString> _jsCheckForAppUpdate();

@JS('registerUpdateCallback')
external void _jsRegisterUpdateCallback(JSFunction callback);

@JS('_pwaRemoteVersion')
external JSString? get _jsRemoteVersion;

@JS('_pwaRemoteBuild')
external JSString? get _jsRemoteBuild;

/// Possible results of a version update check.
enum UpdateStatus { available, upToDate, error }

/// Info about an available update.
class UpdateInfo {
  final UpdateStatus status;
  final String? version;
  final String? build;
  const UpdateInfo(this.status, {this.version, this.build});
}

/// Triggers the reload overlay and reloads the page.
void applyUpdate() => _jsApplyPWAUpdate();

/// Checks version.json for a new release.
/// Returns [UpdateInfo] with status and version details when available.
Future<UpdateInfo> checkForUpdate() async {
  try {
    final result = await _jsCheckForAppUpdate().toDart;
    final value = result.toDart;
    switch (value) {
      case 'available':
        final version = _jsRemoteVersion?.toDart;
        final build = _jsRemoteBuild?.toDart;
        return UpdateInfo(UpdateStatus.available, version: version, build: build);
      case 'upToDate':
        return UpdateInfo(UpdateStatus.upToDate);
      default:
        return UpdateInfo(UpdateStatus.error);
    }
  } catch (_) {
    return UpdateInfo(UpdateStatus.error);
  }
}

/// Registers a callback invoked when [checkForAppUpdate] detects a version mismatch.
void registerUpdateCallback(void Function() callback) {
  try {
    _jsRegisterUpdateCallback(callback.toJS);
  } catch (_) {}
}
