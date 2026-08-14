import '../tracing/span.dart';
import 'transport.dart';

/// In-memory span queue that drains via `spans/ingestBatch`.
class SpanQueue {
  SpanQueue({
    required Transport transport,
    this.maxBatchSize = 50,
    this.flushIntervalMs = 2000,
    void Function(TransportException error)? onError,
    DateTime Function()? clock,
  })  : _transport = transport,
        _onError = onError,
        _clock = clock ?? DateTime.now;

  final Transport _transport;
  final int maxBatchSize;
  final int flushIntervalMs;
  final void Function(TransportException error)? _onError;
  final DateTime Function() _clock;

  final List<_QueuedSpan> _buffer = [];
  bool _draining = false;
  bool _closed = false;

  void enqueue(FinishedSpan span) {
    if (_closed) {
      return;
    }
    _buffer.add(_QueuedSpan(span: span, enqueuedAt: _clock()));
    if (_shouldFlush()) {
      // ignore: discarded_futures
      flush();
    }
  }

  Future<void> flush() async {
    if (_draining || _buffer.isEmpty) {
      return;
    }
    _draining = true;
    try {
      while (_buffer.isNotEmpty) {
        final take =
            _buffer.length < maxBatchSize ? _buffer.length : maxBatchSize;
        final slice = _buffer.sublist(0, take);
        _buffer.removeRange(0, take);
        final spans = [for (final item in slice) item.span];
        try {
          await _transport.sendSpanBatch(spans);
        } on TransportException catch (e) {
          _onError?.call(e);
        } catch (e) {
          _onError?.call(TransportException('$e', cause: e));
        }
      }
    } finally {
      _draining = false;
    }
  }

  int get count => _buffer.length;

  Future<void> close() async {
    await flush();
    _closed = true;
  }

  bool _shouldFlush() {
    if (_buffer.length >= maxBatchSize) {
      return true;
    }
    if (flushIntervalMs <= 0 || _buffer.isEmpty) {
      return false;
    }
    final oldest = _buffer.first.enqueuedAt;
    final ageMs = _clock().difference(oldest).inMilliseconds;
    return ageMs >= flushIntervalMs;
  }
}

class _QueuedSpan {
  _QueuedSpan({required this.span, required this.enqueuedAt});

  final FinishedSpan span;
  final DateTime enqueuedAt;
}
