import 'environment.dart';
import 'severity.dart';

/// In-memory event ready to serialize as `IngestEventInput`.
class Event {
  Event({
    required this.message,
    required this.environment,
    required this.level,
    this.eventType,
    this.title,
    this.stackTrace,
    this.release,
    this.commitSha,
    this.userId,
    this.sessionId,
    this.requestId,
    this.url,
    this.tags,
    this.extraJson,
    this.timestamp,
    this.exception,
    this.platform,
    this.traceId,
    this.spanId,
    this.breadcrumbs,
  }) {
    if (message.trim().isEmpty) {
      throw ArgumentError('Event message must not be empty.');
    }
  }

  final String message;
  final Environment environment;
  final SeverityLevel level;
  final String? eventType;
  final String? title;
  final String? stackTrace;
  final String? release;
  final String? commitSha;
  final String? userId;
  final String? sessionId;
  final String? requestId;
  final String? url;
  final Map<String, String>? tags;
  final String? extraJson;
  final String? timestamp;
  final Map<String, Object?>? exception;
  final String? platform;
  final String? traceId;
  final String? spanId;
  final List<Map<String, Object?>>? breadcrumbs;

  Map<String, Object?> toWire() {
    final wire = <String, Object?>{
      '__className__': 'IngestEventInput',
      'message': message,
      'environment': environment.wireValue,
      'level': level.wireValue,
      'eventType': eventType ?? level.toEventType(),
    };

    void put(String key, Object? value) {
      if (value == null) {
        return;
      }
      if (value is String && value.isEmpty) {
        return;
      }
      if (value is Map && value.isEmpty) {
        return;
      }
      wire[key] = value;
    }

    put('title', title);
    put('stackTrace', stackTrace);
    put('exception', exception);
    put('platform', platform);
    put('release', release);
    put('commitSha', commitSha);
    put('userId', userId);
    put('sessionId', sessionId);
    put('requestId', requestId);
    put('url', url);
    put('tags', tags);
    put('extraJson', extraJson);
    put('timestamp', timestamp);
    put('traceId', traceId);
    put('spanId', spanId);
    put('breadcrumbs', breadcrumbs);

    return wire;
  }
}
