import 'dart:math';

/// W3C Trace Context (`traceparent`) helpers.
///
/// Format: `{version}-{trace-id}-{parent-id}-{flags}` e.g.
/// `00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01`.
class Traceparent {
  const Traceparent({
    required this.traceId,
    required this.spanId,
    this.sampled = false,
    this.version = '00',
  });

  /// 32 lowercase hex chars.
  final String traceId;

  /// 16 lowercase hex chars (parent/current span id).
  final String spanId;

  /// `flags` bit 0 — sampled.
  final bool sampled;

  /// Traceparent version; Talaria emits `00`.
  final String version;

  static final RegExp _hex32 = RegExp(r'^[0-9a-f]{32}$');
  static final RegExp _hex16 = RegExp(r'^[0-9a-f]{16}$');
  static final RegExp _header = RegExp(
    r'^([0-9a-f]{2})-([0-9a-f]{32})-([0-9a-f]{16})-([0-9a-f]{2})$',
    caseSensitive: false,
  );

  static const String headerName = 'traceparent';

  /// `00-{traceId}-{spanId}-{flags}`.
  String toHeader() => '$version-$traceId-$spanId-${sampled ? '01' : '00'}';

  /// Parse a `traceparent` header. Returns null when missing or invalid.
  static Traceparent? tryParse(String? header) {
    if (header == null) {
      return null;
    }
    final trimmed = header.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final match = _header.firstMatch(trimmed);
    if (match == null) {
      return null;
    }
    final version = match.group(1)!.toLowerCase();
    final traceId = match.group(2)!.toLowerCase();
    final spanId = match.group(3)!.toLowerCase();
    final flags = match.group(4)!.toLowerCase();
    if (traceId == '0' * 32 || spanId == '0' * 16) {
      return null;
    }
    if (!_hex32.hasMatch(traceId) || !_hex16.hasMatch(spanId)) {
      return null;
    }
    final flagsValue = int.tryParse(flags, radix: 16) ?? 0;
    return Traceparent(
      version: version,
      traceId: traceId,
      spanId: spanId,
      sampled: (flagsValue & 0x01) == 0x01,
    );
  }

  static String newTraceId([Random? random]) => _randomHex(16, random);

  static String newSpanId([Random? random]) => _randomHex(8, random);

  static bool isTraceId(String value) =>
      _hex32.hasMatch(value.toLowerCase()) && value != '0' * 32;

  static bool isSpanId(String value) =>
      _hex16.hasMatch(value.toLowerCase()) && value != '0' * 16;

  static String _randomHex(int byteCount, Random? random) {
    final rng = random ?? Random.secure();
    String hex;
    do {
      final bytes = List<int>.generate(byteCount, (_) => rng.nextInt(256));
      hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    } while (hex == '0' * (byteCount * 2));
    return hex;
  }
}
