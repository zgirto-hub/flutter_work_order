/// Possible results of a version update check.
enum UpdateStatus { available, upToDate, error }

void applyUpdate() {}

Future<UpdateStatus> checkForUpdate() async => UpdateStatus.error;

void registerUpdateCallback(void Function() callback) {}
