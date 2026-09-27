/// Hourly discard rows for `POST /sdk/reportDiscards`.
class DiscardRow {
  const DiscardRow({
    required this.signal,
    required this.reason,
    required this.count,
  });

  final String signal;
  final String reason;
  final int count;
}

/// Allowed [DiscardRow.signal] values.
class DiscardSignal {
  DiscardSignal._();

  static const events = 'events';
  static const spans = 'spans';
  static const analytics = 'analytics';
}

/// Allowed [DiscardRow.reason] values.
class DiscardReason {
  DiscardReason._();

  static const sampleRate = 'sample_rate';
  static const queueOverflow = 'queue_overflow';
  static const signalDisabled = 'signal_disabled';
  static const network = 'network';
}

/// Accumulates discard counts until the next report flush.
class DiscardBuffer {
  final Map<String, int> _counts = {};

  void record({
    required String signal,
    required String reason,
    int count = 1,
  }) {
    if (count < 1) {
      return;
    }
    final key = '$signal|$reason';
    _counts[key] = (_counts[key] ?? 0) + count;
  }

  bool get isEmpty => _counts.isEmpty;

  List<DiscardRow> drain() {
    if (_counts.isEmpty) {
      return const [];
    }
    final rows = <DiscardRow>[];
    for (final entry in _counts.entries) {
      final parts = entry.key.split('|');
      rows.add(
        DiscardRow(signal: parts[0], reason: parts[1], count: entry.value),
      );
    }
    _counts.clear();
    return rows;
  }
}
