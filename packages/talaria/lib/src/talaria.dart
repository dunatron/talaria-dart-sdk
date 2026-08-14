import 'package:http/http.dart' as http;

import 'capture_context.dart';
import 'client.dart';
import 'config.dart';
import 'context/runtime_context.dart';
import 'http/talaria_http_client.dart';
import 'logger.dart';
import 'severity.dart';
import 'tracing/breadcrumbs.dart';
import 'tracing/span.dart';
import 'tracing/trace_context.dart';
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
    RuntimeContext.clearCurrent();
  }

  static void addProcessor(EventProcessor processor) =>
      _requireClient().addProcessor(processor);

  static void addBreadcrumb(Breadcrumb breadcrumb) =>
      _requireClient().addBreadcrumb(breadcrumb);

  static Span startTransaction(
    String name, {
    SpanKind kind = SpanKind.internal,
    Map<String, Object?>? attributes,
    Traceparent? parent,
  }) {
    return _requireClient().startTransaction(
      name,
      kind: kind,
      attributes: attributes,
      parent: parent,
    );
  }

  static Span startSpan(
    String name, {
    SpanKind kind = SpanKind.internal,
    Map<String, Object?>? attributes,
    Span? parent,
  }) {
    return _requireClient().startSpan(
      name,
      kind: kind,
      attributes: attributes,
      parent: parent,
    );
  }

  /// Wrap application HTTP. Never pass the result as the ingest `httpClient`.
  static http.Client wrapHttpClient(http.Client inner) {
    return TalariaHttpClient(inner, client: _requireClient());
  }

  /// W3C `traceparent` for the active span, or null when tracing is off / idle.
  static String? getTraceparent() => _requireClient().getTraceparent();

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
