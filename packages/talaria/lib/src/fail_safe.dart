import 'dart:developer' as developer;

/// Fail-safe diagnostics (Talaria workspace D19).
///
/// Talaria never throws into the host app. A missing or invalid key, or a bad
/// option, disables the client with one warning per process. Transport faults
/// are logged at most once per channel per [transportLogInterval].
class FailSafe {
  FailSafe._();

  /// Time between two log lines for the same channel.
  static const transportLogInterval = Duration(minutes: 1);

  /// Where warnings go. Defaults to `print` (once per process) for the
  /// disabled warning and `dart:developer` log for transport faults. Tests and
  /// apps with their own logger may replace it.
  static void Function(String message)? sink;

  static bool _disabledWarned = false;
  static final Map<String, DateTime> _lastLog = {};

  /// At most the first 8 characters of [key], for log lines.
  static String keyPreview(String? key) {
    final trimmed = key?.trim() ?? '';
    if (trimmed.isEmpty) return '';
    return trimmed.length > 8 ? '${trimmed.substring(0, 8)}…' : trimmed;
  }

  /// The "Talaria is disabled" warning, once per process. Returns true when
  /// it was logged.
  static bool warnDisabledOnce(String reason) {
    if (_disabledWarned) return false;
    _disabledWarned = true;
    _emit(
      '[Talaria] Talaria is disabled: $reason. '
      'The app keeps running and nothing is sent.',
      visible: true,
    );
    return true;
  }

  /// Log a transport or internal fault at most once per
  /// [transportLogInterval] per [channel]. Returns true when it was logged.
  static bool logRateLimited(String channel, String message, {DateTime? now}) {
    final at = now ?? DateTime.now();
    final last = _lastLog[channel];
    if (last != null && at.difference(last) < transportLogInterval) {
      return false;
    }
    _lastLog[channel] = at;
    _emit(message, visible: false);
    return true;
  }

  static void _emit(String message, {required bool visible}) {
    try {
      final custom = sink;
      if (custom != null) {
        custom(message);
        return;
      }
      if (visible) {
        // One line per process, so a bad key is visible in server logs too.
        // ignore: avoid_print
        print(message);
      } else {
        developer.log(message, name: 'talaria');
      }
    } catch (_) {
      // A broken logger must not reach the host.
    }
  }

  /// Reset between tests.
  static void reset() {
    _disabledWarned = false;
    _lastLog.clear();
  }
}
