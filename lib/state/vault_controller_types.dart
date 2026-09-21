enum AutoLockPreset {
  oneMinute(Duration(minutes: 1), '1 分钟'),
  twoMinutes(Duration(minutes: 2), '2 分钟'),
  fiveMinutes(Duration(minutes: 5), '5 分钟'),
  fifteenMinutes(Duration(minutes: 15), '15 分钟');

  const AutoLockPreset(this.duration, this.label);

  final Duration duration;
  final String label;
}

class VaultOperationResult {
  const VaultOperationResult({this.error});

  const VaultOperationResult.success() : error = null;

  final Object? error;

  bool get succeeded => error == null;
}
