import '../context/runtime_context.dart';

/// Wire `AnalyticsEventKindWire`.
enum AnalyticsEventKind {
  track,
  page,
  screen,
  identify,
}

/// Default names when the caller omits [AnalyticsEvent.name].
class AnalyticsEventNames {
  AnalyticsEventNames._();

  static const pageview = r'$pageview';
  static const screen = r'$screen';
  static const identify = r'$identify';
}

/// In-memory analytics event ready to serialize as `IngestAnalyticsEventInput`.
class AnalyticsEvent {
  AnalyticsEvent({
    required this.eventId,
    required this.name,
    required this.kind,
    required this.anonymousId,
    required this.sessionId,
    required this.timestamp,
    this.userId,
    this.replayId,
    this.traceId,
    this.spanId,
    this.requestId,
    this.platform,
    this.environment,
    this.release,
    this.url,
    this.path,
    this.title,
    this.referrer,
    this.utmSource,
    this.utmMedium,
    this.utmCampaign,
    this.utmTerm,
    this.utmContent,
    this.propertiesJson,
    this.browserName,
    this.browserVersion,
    this.browserEngine,
    this.osName,
    this.osVersion,
    this.device,
    this.locale,
    this.timezone,
    this.webview,
    this.webviewHost,
    this.bot,
    this.botName,
    this.botKind,
    this.webdriver,
    this.userAgent,
  });

  final String eventId;
  final String name;
  final AnalyticsEventKind kind;
  final String anonymousId;
  final String sessionId;
  final DateTime timestamp;
  final String? userId;
  final String? replayId;
  final String? traceId;
  final String? spanId;
  final String? requestId;
  final String? platform;
  final String? environment;
  final String? release;
  final String? url;
  final String? path;
  final String? title;
  final String? referrer;
  final String? utmSource;
  final String? utmMedium;
  final String? utmCampaign;
  final String? utmTerm;
  final String? utmContent;
  final String? propertiesJson;
  final String? browserName;
  final String? browserVersion;
  final String? browserEngine;
  final String? osName;
  final String? osVersion;
  final String? device;
  final String? locale;
  final String? timezone;
  final bool? webview;
  final String? webviewHost;
  final bool? bot;
  final String? botName;
  final String? botKind;
  final bool? webdriver;
  final String? userAgent;

  Map<String, Object?> toWire() {
    final wire = <String, Object?>{
      '__className__': 'IngestAnalyticsEventInput',
      'eventId': eventId,
      'name': name,
      'kind': kind.name,
      'anonymousId': anonymousId,
      'sessionId': sessionId,
      'timestamp': RuntimeContext.isoTimestamp(timestamp),
    };

    void put(String key, Object? value) {
      if (value == null) {
        return;
      }
      if (value is String && value.isEmpty) {
        return;
      }
      wire[key] = value;
    }

    put('userId', userId);
    put('replayId', replayId);
    put('traceId', traceId);
    put('spanId', spanId);
    put('requestId', requestId);
    put('platform', platform);
    put('environment', environment);
    put('release', release);
    put('url', url);
    put('path', path);
    put('title', title);
    put('referrer', referrer);
    put('utmSource', utmSource);
    put('utmMedium', utmMedium);
    put('utmCampaign', utmCampaign);
    put('utmTerm', utmTerm);
    put('utmContent', utmContent);
    put('propertiesJson', propertiesJson);
    put('browserName', browserName);
    put('browserVersion', browserVersion);
    put('browserEngine', browserEngine);
    put('osName', osName);
    put('osVersion', osVersion);
    put('device', device);
    put('locale', locale);
    put('timezone', timezone);
    if (webview == true) {
      wire['webview'] = true;
    }
    put('webviewHost', webviewHost);
    if (bot == true) {
      wire['bot'] = true;
    }
    put('botName', botName);
    put('botKind', botKind);
    if (webdriver == true) {
      wire['webdriver'] = true;
    }
    put('userAgent', userAgent);

    return wire;
  }
}

/// Host-provided page fields (Flutter web location, current route, …).
class AnalyticsPageContext {
  const AnalyticsPageContext({
    this.url,
    this.path,
    this.title,
    this.referrer,
  });

  final String? url;
  final String? path;
  final String? title;
  final String? referrer;
}

typedef AnalyticsContextProvider = AnalyticsPageContext Function();
