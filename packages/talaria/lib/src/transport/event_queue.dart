import '../event.dart';
import 'transport.dart';

/// In-memory queue that drains via ingestBatch on size or age thresholds.
class EventQueue {
  EventQueue({
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

  final List<_QueuedEvent> _buffer = [];
  bool _draining = false;
  bool _closed = false;

  void enqueue(Event event) {
    if (_closed) {
      return;
    }
    _buffer.add(_QueuedEvent(event: event, enqueuedAt: _clock()));
    if (_shouldFlush()) {
      // Fire-and-forget drain; callers can also await [flush].
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
        final events = [for (final item in slice) item.event];
        try {
          await _transport.sendBatch(events);
        } on TransportException catch (e) {
          _onError?.call(e);
          // Drop failed batch — no poison-pill retry loop in v1.
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

class _QueuedEvent {
  _QueuedEvent({required this.event, required this.enqueuedAt});

  final Event event;
  final DateTime enqueuedAt;
}
