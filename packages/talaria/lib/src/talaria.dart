import 'capture_context.dart';
import 'client.dart';
import 'config.dart';
import 'logger.dart';
import 'severity.dart';
import 'transport/transport.dart';

/// Static facade mirroring the browser / PHP SDK singleton API.
class Talaria {
  Talaria._();

  static TalariaClient? _client;

  /// Initialize the global client. Subsequent calls are ignored.
  static Future<TalariaClient> init(
    TalariaOptions options, {
    Transport? transport,
  }) async {
    if (_client != null) {
      // ignore: avoid_print
      assert(() {
        // ignore: avoid_print
        print(
            '[Talaria] init() called more than once; ignoring subsequent init.');
        return true;
      }());
      return _client!;
    }
    _client = TalariaClient(options, transport: transport);
    return _client!;
  }

  static TalariaClient? getClient() => _client;

  static TalariaLogger logger({
    String? name,
    Map<String, String>? tags,
    SeverityLevel? minLevel,
  }) {
    return _requireClient().logger(
      name: name,
      tags: tags,
      minLevel: minLevel,
    );
  }

  static bool isEnforceDefaultLevel() =>
      _requireClient().isEnforceDefaultLevel();

  static void setEnforceDefaultLevel(bool enforce) =>
      _requireClient().setEnforceDefaultLevel(enforce);

  static TalariaLogger withTags(Map<String, String> tags) =>
      _requireClient().withTags(tags);

  static Future<void> debug(String message, {CaptureContext? context}) =>
      _requireClient().debug(message, context: context);

  static Future<void> info(String message, {CaptureContext? context}) =>
      _requireClient().info(message, context: context);

  static Future<void> warning(String message, {CaptureContext? context}) =>
      _requireClient().warning(message, context: context);

  static Future<void> warn(String message, {CaptureContext? context}) =>
      _requireClient().warn(message, context: context);

  static Future<void> error(String message, {CaptureContext? context}) =>
      _requireClient().error(message, context: context);

  static Future<void> fatal(String message, {CaptureContext? context}) =>
      _requireClient().fatal(message, context: context);

  static Future<void> log(
    Object level,
    String message, {
    CaptureContext? context,
  }) =>
      _requireClient().log(level, message, context: context);

  static SeverityLevel getMinLevel() => _requireClient().getMinLevel();

  static void setMinLevel(Object level) => _requireClient().setMinLevel(level);

  static bool isLevelEnabled(Object level) =>
      _requireClient().isLevelEnabled(level);

  static Future<void> captureException(
    Object error, {
    StackTrace? stackTrace,
    CaptureContext? context,
  }) =>
      _requireClient().captureException(
        error,
        stackTrace: stackTrace,
        context: context,
      );

  static Future<void> captureMessage(
    String message, {
    Object level = SeverityLevel.info,
    CaptureContext? context,
  }) =>
      _requireClient().captureMessage(
        message,
        level: level,
        context: context,
      );

  static Future<void> flush() async {
    await _client?.flush();
  }

  static Future<void> close() async {
    await _client?.close();
    _client = null;
  }

  /// Reset singleton between tests.
  static Future<void> reset() async {
    await close();
  }

  static TalariaClient _requireClient() {
    final client = _client;
    if (client == null) {
      throw StateError(
          'Talaria.init() must be called before capturing events.');
    }
    return client;
  }
}
