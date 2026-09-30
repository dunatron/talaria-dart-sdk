import 'package:talaria/talaria.dart';

/// Mid-request local flag evaluation helper for Serverpod / server Dart.
///
/// Prefer [TalariaFlags.loadDefinitions] once at process start (API key needs
/// `flags:definitions`), then call [boolVariation] / [stringVariation] /
/// [jsonVariation] per request. Poll refreshes definitions on TTL; there is
/// no background update while a mobile client is suspended.
class TalariaServerpodFlags {
  TalariaServerpodFlags._();

  static TalariaFlags get _flags {
    final client = Talaria.getClient();
    if (client == null) {
      throw StateError('TalariaServerpod.init / Talaria.init required first');
    }
    return client.flags;
  }

  /// Download definitions into the shared client (idempotent after first success).
  static Future<void> ensureLocalDefinitions() => _flags.loadDefinitions();

  static Future<bool> boolVariation(String key, bool defaultValue) =>
      _flags.boolVariation(key, defaultValue);

  static Future<String> stringVariation(String key, String defaultValue) =>
      _flags.stringVariation(key, defaultValue);

  static Future<Object?> jsonVariation(String key, Object? defaultValue) =>
      _flags.jsonVariation(key, defaultValue);

  static Future<void> setContext({
    String? userId,
    String? organizationId,
    Map<String, String>? attributes,
  }) {
    return _flags.setContext(
      userId: userId,
      organizationId: organizationId,
      attributes: attributes,
    );
  }
}
