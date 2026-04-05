/// Possible results of a version update check.
enum UpdateStatus { available, upToDate, error }

/// Info about an available update.
class UpdateInfo {
  final UpdateStatus status;
  final String? version;
  final String? build;
  const UpdateInfo(this.status, {this.version, this.build});
}

void applyUpdate() {}

Future<UpdateInfo> checkForUpdate() async => UpdateInfo(UpdateStatus.error);

void registerUpdateCallback(void Function() callback) {}
