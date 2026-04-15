String formatStageLatency(int? ms) {
  if (ms == null) return '—';
  if (ms < 100) return '<1s';
  if (ms < 60000) {
    final seconds = ms / 1000.0;
    return '${seconds.toStringAsFixed(1)}s';
  }
  final totalSeconds = ms ~/ 1000;
  final minutes = totalSeconds ~/ 60;
  final remSeconds = totalSeconds % 60;
  return '${minutes}m ${remSeconds}s';
}
