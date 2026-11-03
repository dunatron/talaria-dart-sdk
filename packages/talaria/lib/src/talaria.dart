import 'package:http/http.dart' as http;

import 'analytics/analytics.dart';
import 'capture_context.dart';
import 'client.dart';
import 'config.dart';
import 'context/runtime_context.dart';
import 'flags/flags_client.dart';
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

  /// Answers facade calls before [init]: a disabled no-op client, no warning.
  static TalariaClient? _detached;

  /// Initialize the global client. Subsequent calls are ignored.
  ///
  /// Never throws (D19). A missing or invalid key, or a bad option, returns a
  /// disabled no-op client ([TalariaClient.isEnabled] is false) and logs one
  /// warning per process.
  static Future<TalariaClient> init(
    TalariaOptions options, {
    Transport? transport,
  }) async {
    final previous = _client;
    if (previous != null && !previous.isEnabled) {
      // A disabled client (bad key) does not block a later, valid init.
      await previous.close();
      _client = null;
    }
    if (_client != null) {
      // ignore: avoid_print
      assert(() {
        // ignore: avoid_print
        print(
          '[Talaria] init() called more than once; ignoring subsequent init.',
        );
        return true;
      }());
      return _client!;
    }
    try {
      _client = TalariaClient(options, transport: transport);
    } catch (e) {
      _client = TalariaClient(
        TalariaOptions(apiKey: '', disabledReason: 'init failed ($e)'),
      );
    }
    return _client!;
  }

  /// True after a successful [init] with a valid key, until [close].
  static bool get isEnabled => _client?.isEnabled ?? false;

  static TalariaClient? getClient() => _client;

  /// Product analytics (`track` / `page` / `screen` / `identify`).
  static TalariaAnalytics get analytics => _requireClient().analytics;

  /// Feature flags (`boolVariation` / `stringVariation` / `jsonVariation`).
  static TalariaFlags get flags => _requireClient().flags;

  static void setUser(String? userId) => _requireClient().setUser(userId);

  static String get anonymousId => _requireClient().anonymousId;

  static String get sessionId => _requireClient().sessionId;

  static TalariaLogger logger({
    String? name,
    Map<String, String>? tags,
    SeverityLevel? minLevel,
  }) {
    return _requireClient().logger(name: name, tags: tags, minLevel: minLevel);
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
      _requireClient().captureMessage(message, level: level, context: context);

  static Future<void> flush() async {
    await _client?.flush();
  }

  static Future<void> close() async {
    await _client?.close();
    _client = null;
    _detached = null;
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

  static void setRecordQuerySpans(bool record) {
    _requireClient().setRecordQuerySpans(record);
  }

  static T withoutQuerySpans<T>(T Function() body) {
    return _requireClient().withoutQuerySpans(body);
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
    TalariaClient.clearPolicyCache();
  }

  /// The global client, or a disabled no-op client before [init] (D19).
  static TalariaClient _requireClient() {
    return _client ??
        (_detached ??= TalariaClient(
          TalariaOptions(
            apiKey: '',
            disabledReason: 'Talaria.init() has not been called',
          ),
          warnIfDisabled: false,
        ));
  }
}
