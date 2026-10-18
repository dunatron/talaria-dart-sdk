import 'dart:math';

import 'discards.dart';
import 'transport.dart';

/// What a queue does with a batch that failed to export.
class ExportFailure {
  const ExportFailure(this.reason, {this.requeue = false});

  /// Discard reason if the batch is dropped.
  final String reason;

  /// Put the batch back and send it after the pause (rate limits only).
  final bool requeue;
}

/// Backoff for one ingest signal (events, spans, analytics, discards).
///
/// - **HTTP 429**: wait at least `Retry-After`, growing exponentially on
///   repeats, plus up to 20% jitter. The batch is kept and sent again.
/// - **HTTP 402**: drop the batch as `quota` and stop sending until the
///   quota period resets, re-checking at most every [maxQuotaPause] so a plan
///   upgrade takes effect. Without a reset time, pause for [quotaPause].
/// - **Network errors, timeouts, 408, 5xx, `retry: true`**: drop the batch as
///   `network` and pause with exponential backoff and jitter.
/// - **Anything else** (bad key, validation): drop as `network`, no pause.
///   The client disables ingest for permanent errors itself.
///
/// While paused, queues hold their buffers and send nothing, even on an
/// explicit flush. During a quota pause new items are refused at once.
class IngestBackoff {
  IngestBackoff({
    DateTime Function()? clock,
    Random? random,
    this.baseDelay = const Duration(seconds: 1),
    this.maxDelay = const Duration(minutes: 5),
    this.quotaPause = const Duration(minutes: 10),
    this.maxQuotaPause = const Duration(hours: 1),
  })  : _clock = clock ?? DateTime.now,
        _random = random ?? Random();

  /// First transient-failure pause; doubles on each consecutive failure.
  final Duration baseDelay;

  /// Ceiling for exponential pauses. A longer `Retry-After` still wins.
  final Duration maxDelay;

  /// Quota pause when the server gives no reset time.
  final Duration quotaPause;

  /// Longest single quota pause before sending again to re-check.
  final Duration maxQuotaPause;

  final DateTime Function() _clock;
  final Random _random;

  DateTime? _pausedUntil;
  String? _pauseReason;
  int _failures = 0;

  /// True while exports must wait.
  bool get isPaused {
    final until = _pausedUntil;
    return until != null && _clock().isBefore(until);
  }

  /// Time left on the current pause, or null when not paused.
  Duration? get remaining =>
      isPaused ? _pausedUntil!.difference(_clock()) : null;

  /// Why exports are paused: `rate_limited`, `quota` or `network`.
  String? get pauseReason => isPaused ? _pauseReason : null;

  /// Discard reason for a new item that must be refused now, or null to
  /// accept it. Only an exhausted quota refuses new items.
  String? get refuseReason =>
      pauseReason == DiscardReason.quota ? DiscardReason.quota : null;

  /// Discard reason when a full buffer drops an item. A buffer that filled
  /// up behind a rate limit is a rate-limit drop.
  String get overflowReason => pauseReason == DiscardReason.rateLimited
      ? DiscardReason.rateLimited
      : DiscardReason.queueOverflow;

  /// Discard reason for items still held when the queue closes while paused.
  String get closeReason => pauseReason ?? DiscardReason.network;

  void onSuccess() {
    _failures = 0;
    _pausedUntil = null;
    _pauseReason = null;
  }

  ExportFailure onFailure(TransportException error) {
    final now = _clock();
    if (error.isQuotaExceeded) {
      _pause(now.add(quotaPauseFor(error, now)), DiscardReason.quota);
      return const ExportFailure(DiscardReason.quota);
    }
    if (error.isRateLimited) {
      _failures++;
      final floor = error.retryAfter ?? Duration.zero;
      final grown = _exponential(_failures);
      final wait = floor > grown ? floor : grown;
      _pause(now.add(_jitterUp(wait)), DiscardReason.rateLimited);
      return const ExportFailure(DiscardReason.rateLimited, requeue: true);
    }
    if (error.isTransient) {
      _failures++;
      final grown = _exponential(_failures);
      final floor = error.retryAfter ?? Duration.zero;
      final wait = floor > grown ? floor : _fullJitter(grown);
      _pause(now.add(wait), DiscardReason.network);
      return const ExportFailure(DiscardReason.network);
    }
    return const ExportFailure(DiscardReason.network);
  }

  /// Pause another signal's meter for an exhausted quota (HTTP 402 whose
  /// `meter` names it).
  void pauseForQuota(TransportException error) {
    final now = _clock();
    _pause(now.add(quotaPauseFor(error, now)), DiscardReason.quota);
  }

  /// Until the reset (body `resetAt`, else `Retry-After`), else
  /// [quotaPause]; at most [maxQuotaPause], at least one second.
  Duration quotaPauseFor(TransportException error, DateTime now) {
    final reset = error.resetAt;
    var wait = reset != null
        ? reset.difference(now.toUtc())
        : (error.retryAfter ?? quotaPause);
    if (wait > maxQuotaPause) wait = maxQuotaPause;
    if (wait < const Duration(seconds: 1)) wait = const Duration(seconds: 1);
    return wait;
  }

  void _pause(DateTime until, String reason) {
    final current = _pausedUntil;
    // Never shorten a longer pause already in force (e.g. quota vs 429).
    if (current != null && current.isAfter(until) && isPaused) return;
    _pausedUntil = until;
    _pauseReason = reason;
  }

  Duration _exponential(int failures) {
    final shift = (failures - 1).clamp(0, 20);
    final ms = baseDelay.inMilliseconds * (1 << shift);
    return ms >= maxDelay.inMilliseconds
        ? maxDelay
        : Duration(milliseconds: ms);
  }

  /// [wait] plus up to 20%, so clients told the same `Retry-After` don't
  /// all come back in the same second.
  Duration _jitterUp(Duration wait) => Duration(
        milliseconds: wait.inMilliseconds +
            (_random.nextDouble() * wait.inMilliseconds * 0.2).round(),
      );

  /// Between half and all of [wait].
  Duration _fullJitter(Duration wait) => Duration(
        milliseconds:
            (wait.inMilliseconds * (0.5 + _random.nextDouble() * 0.5)).round(),
      );
}
