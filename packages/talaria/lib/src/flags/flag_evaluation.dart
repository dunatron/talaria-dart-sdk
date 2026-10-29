import 'dart:convert';

/// One flag evaluation returned by `POST /flags/evaluate`.
class FlagEvaluationResult {
  const FlagEvaluationResult({
    required this.key,
    required this.variationKey,
    required this.value,
    required this.version,
    this.reason,
    this.valueJson,
  });

  final String key;
  final String variationKey;

  /// Decoded [valueJson] (bool, String, num, Map, List, or null).
  final Object? value;

  final int version;
  final String? reason;

  /// Raw wire payload when present.
  final String? valueJson;

  factory FlagEvaluationResult.fromWire(Map<String, Object?> raw) {
    final key = (raw['key'] as String?)?.trim() ?? '';
    final variationKey = (raw['variationKey'] as String?)?.trim() ?? '';
    final version = (raw['version'] as num?)?.toInt() ?? 0;
    final reason = raw['reason'] as String?;
    final valueJson = raw['valueJson'] as String?;
    return FlagEvaluationResult(
      key: key,
      variationKey: variationKey,
      value: decodeValueJson(valueJson),
      version: version,
      reason: reason,
      valueJson: valueJson,
    );
  }

  Map<String, Object?> toCacheJson() => {
        'key': key,
        'variationKey': variationKey,
        'valueJson': valueJson ?? encodeValueJson(value),
        'version': version,
        if (reason != null) 'reason': reason,
      };

  static Object? decodeValueJson(String? valueJson) {
    if (valueJson == null || valueJson.isEmpty) {
      return null;
    }
    try {
      return jsonDecode(valueJson);
    } catch (_) {
      return valueJson;
    }
  }

  static String encodeValueJson(Object? value) {
    try {
      return jsonEncode(value);
    } catch (_) {
      return jsonEncode(value?.toString());
    }
  }
}
