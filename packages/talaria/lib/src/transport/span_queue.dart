import 'dart:async';

import '../tracing/span.dart';
import 'transport.dart';

/// In-memory span queue that drains via `spans/ingestBatch`.
///
/// Spans are exported in batches, not one request per traced call:
/// - when [maxBatchSize] spans are buffered, or
/// - [flushIntervalMs] after the oldest buffered span was enqueued.
///
/// Automatic exports are spaced at least `60000 / maxExportsPerMinute` ms
/// apart, so a busy process sends at most [maxExportsPerMinute] span
/// batches a minute (the server's default per-key limit is 100 a minute
/// per signal). Spans beyond [maxBufferSize] are dropped and reported as
/// `queue_overflow`.
///
/// [flush] and [close] still drain everything at once.
class SpanQueue {
  SpanQueue({
    required Transport transport,
    this.maxBatchSize = 200,
    this.maxBufferSize = 2048,
    this.flushIntervalMs = 5000,
    this.maxExportsPerMinute = 30,
    this.timers = true,
    void Function(TransportException error)? onError,
    void Function(int count, String reason)? onDiscard,
    DateTime Function()? clock,
  })  : assert(maxBatchSize > 0),
        assert(maxExportsPerMinute > 0),
        _transport = transport,
        _onError = onError,
        _onDiscard = onDiscard,
        _clock = clock ?? DateTime.now;

  final Transport _transport;
  final int maxBatchSize;
  final int maxBufferSize;

  /// Longest a span waits before a timed export. 0 turns the timer off, so
  /// spans go out on a full batch or an explicit [flush] only.
  final int flushIntervalMs;

  /// Ceiling on automatic exports. Explicit [flush] calls are not limited.
  final int maxExportsPerMinute;

  /// False creates no timers (`TalariaOptions.flushIntervalMs: 0`, widget
  /// tests). A due batch is then sent on the next enqueue, or by [flush].
  final bool timers;

  final void Function(TransportException error)? _onError;
  final void Function(int count, String reason)? _onDiscard;
  final DateTime Function() _clock;

  final List<_QueuedSpan> _buffer = [];
  Future<void>? _inflight;
  Timer? _timer;
  DateTime? _timerDue;
  DateTime? _lastExportAt;
  bool _closed = false;

  /// Minimum gap between automatic exports.
  Duration get minExportSpacing =>
      Duration(milliseconds: (60000 / maxExportsPerMinute).ceil());

  int get count => _buffer.length;

  /// True while a timed or spaced export is scheduled.
  bool get hasPendingExport => _timer != null;

  void enqueue(FinishedSpan span) {
    if (_closed) {
      return;
    }
    if (_buffer.length >= maxBufferSize) {
      _onDiscard?.call(1, 'queue_overflow');
      return;
    }
    _buffer.add(_QueuedSpan(span: span, enqueuedAt: _clock()));
    _schedule();
  }

  /// Sends every buffered span now, waiting for an export already in flight.
  Future<void> flush() async {
    _cancelTimer();
    while (true) {
      final running = _inflight;
      if (running != null) {
        await running;
        continue;
      }
      if (_buffer.isEmpty) {
        return;
      }
      await _exportBatch();
    }
  }

  Future<void> close() async {
    _cancelTimer();
    await flush();
    _closed = true;
  }

  /// Arms the timer for the next automatic export, if one is due.
  void _schedule() {
    if (_closed || _buffer.isEmpty || _inflight != null) {
      return;
    }
    final now = _clock();
    final Duration wait;
    if (_buffer.length >= maxBatchSize) {
      wait = _spacingRemaining(now);
    } else if (flushIntervalMs > 0) {
      final age = now.difference(_buffer.first.enqueuedAt);
      final untilDue = Duration(milliseconds: flushIntervalMs) - age;
      final spacing = _spacingRemaining(now);
      wait = untilDue > spacing ? untilDue : spacing;
    } else {
      return;
    }
    if (wait <= Duration.zero) {
      _cancelTimer();
      // ignore: discarded_futures
      _automaticExport();
      return;
    }
    if (!timers) {
      return;
    }
    final due = now.add(wait);
    final armed = _timerDue;
    if (_timer != null && armed != null && !due.isBefore(armed)) {
      return;
    }
    _cancelTimer();
    _timerDue = due;
    _timer = Timer(wait, () {
      _timer = null;
      _timerDue = null;
      // ignore: discarded_futures
      _automaticExport();
    });
  }

  Duration _spacingRemaining(DateTime now) {
    final last = _lastExportAt;
    if (last == null) {
      return Duration.zero;
    }
    final remaining = minExportSpacing - now.difference(last);
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// One batch, then re-arm for whatever is left (timers only; without
  /// timers the next enqueue or [flush] picks it up).
  Future<void> _automaticExport() async {
    if (_inflight != null || _buffer.isEmpty) {
      return;
    }
    await _exportBatch();
    if (timers) {
      _schedule();
    }
  }

  Future<void> _exportBatch() {
    final take = _buffer.length < maxBatchSize ? _buffer.length : maxBatchSize;
    final slice = _buffer.sublist(0, take);
    _buffer.removeRange(0, take);
    final spans = [for (final item in slice) item.span];
    _lastExportAt = _clock();
    final future = _send(spans);
    _inflight = future;
    return future.whenComplete(() {
      if (identical(_inflight, future)) {
        _inflight = null;
      }
    });
  }

  Future<void> _send(List<FinishedSpan> spans) async {
    try {
      await _transport.sendSpanBatch(spans);
    } on TransportException catch (e) {
      _onDiscard?.call(spans.length, 'network');
      _onError?.call(e);
    } catch (e) {
      _onDiscard?.call(spans.length, 'network');
      _onError?.call(TransportException('$e', cause: e));
    }
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
    _timerDue = null;
  }
}

class _QueuedSpan {
  _QueuedSpan({required this.span, required this.enqueuedAt});

  final FinishedSpan span;
  final DateTime enqueuedAt;
}
