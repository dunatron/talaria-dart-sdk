/// Wire severity levels accepted by Talaria ingest.
enum SeverityLevel {
  debug('debug'),
  info('info'),
  warning('warning'),
  error('error'),
  fatal('fatal');

  const SeverityLevel(this.wireValue);

  final String wireValue;

  /// Parse wire or common aliases (`warn`, `err`, `critical`, …).
  static SeverityLevel? tryFromMixed(Object level) {
    if (level is SeverityLevel) {
      return level;
    }
    final normalized = level.toString().trim().toLowerCase();
    return switch (normalized) {
      'debug' => SeverityLevel.debug,
      'info' || 'notice' => SeverityLevel.info,
      'warning' || 'warn' => SeverityLevel.warning,
      'error' || 'err' => SeverityLevel.error,
      'critical' || 'alert' || 'emergency' || 'fatal' => SeverityLevel.fatal,
      _ => null,
    };
  }

  /// Map severity to ingest `eventType` (fatal has no dedicated wire value).
  String toEventType() {
    return switch (this) {
      SeverityLevel.fatal || SeverityLevel.error => 'error',
      SeverityLevel.warning => 'warning',
      SeverityLevel.debug => 'debug',
      SeverityLevel.info => 'info',
    };
  }

  /// Rank from lowest (0) to highest (4) severity.
  int get rank {
    return switch (this) {
      SeverityLevel.debug => 0,
      SeverityLevel.info => 1,
      SeverityLevel.warning => 2,
      SeverityLevel.error => 3,
      SeverityLevel.fatal => 4,
    };
  }

  /// True when this level is at least as severe as [min].
  bool atLeast(SeverityLevel min) => rank >= min.rank;

  /// Higher (stricter floor) of two severities.
  static SeverityLevel max(SeverityLevel a, SeverityLevel b) =>
      a.rank >= b.rank ? a : b;
}
