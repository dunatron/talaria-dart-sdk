import '../event.dart';
import 'ingest_backoff.dart';
import 'transport.dart';

/// In-memory queue that drains via ingestBatch on size or age thresholds.
class EventQueue {
  EventQueue({
    required Transport transport,
    this.maxBatchSize = 50,
    this.maxBufferSize = 200,
    this.flushIntervalMs = 2000,
    void Function(TransportException error)? onError,
    void Function(int count, String reason)? onDiscard,
    DateTime Function()? clock,
    IngestBackoff? backoff,
  })  : _transport = transport,
        _backoff = backoff,
        _onError = onError,
        _onDiscard = onDiscard,
        _clock = clock ?? DateTime.now;

  final Transport _transport;
  final int maxBatchSize;
  final int maxBufferSize;
  final int flushIntervalMs;
  final void Function(TransportException error)? _onError;
  final void Function(int count, String reason)? _onDiscard;
  final DateTime Function() _clock;
  final IngestBackoff? _backoff;

  final List<_QueuedEvent> _buffer = [];
  bool _draining = false;
  bool _closed = false;

  void enqueue(Event event) {
    if (_closed) {
      return;
    }
    final refused = _backoff?.refuseReason;
    if (refused != null) {
      _onDiscard?.call(1, refused);
      return;
    }
    if (_buffer.length >= maxBufferSize) {
      _onDiscard?.call(1, _backoff?.overflowReason ?? 'queue_overflow');
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
    if (_draining || _buffer.isEmpty || _paused) {
      return;
    }
    _draining = true;
    try {
      while (_buffer.isNotEmpty && !_paused) {
        final take =
            _buffer.length < maxBatchSize ? _buffer.length : maxBatchSize;
        final slice = _buffer.sublist(0, take);
        _buffer.removeRange(0, take);
        final events = [for (final item in slice) item.event];
        try {
          await _transport.sendBatch(events);
          _backoff?.onSuccess();
        } on TransportException catch (e) {
          _failed(slice, e);
          _onError?.call(e);
        } catch (e) {
          final error = TransportException('$e', cause: e);
          _failed(slice, error);
          _onError?.call(error);
        }
      }
    } finally {
      _draining = false;
    }
  }

  int get count => _buffer.length;

  Future<void> close() async {
    await flush();
    if (_buffer.isNotEmpty) {
      // Still paused: nothing more will be sent.
      _onDiscard?.call(_buffer.length, _backoff?.closeReason ?? 'network');
      _buffer.clear();
    }
    _closed = true;
  }

  bool get _paused => _backoff?.isPaused ?? false;

  /// Rate-limited batches go back to the front, as far as the buffer allows;
  /// everything else is dropped with the backoff's reason.
  void _failed(List<_QueuedEvent> slice, TransportException error) {
    final outcome =
        _backoff?.onFailure(error) ?? const ExportFailure('network');
    if (!outcome.requeue) {
      _onDiscard?.call(slice.length, outcome.reason);
      return;
    }
    final room = maxBufferSize - _buffer.length;
    final keep = room <= 0 ? 0 : (room < slice.length ? room : slice.length);
    _buffer.insertAll(0, slice.sublist(0, keep));
    if (keep < slice.length) {
      _onDiscard?.call(slice.length - keep, outcome.reason);
    }
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
