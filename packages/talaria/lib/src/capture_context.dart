import 'severity.dart';

/// Per-call capture context bag.
class CaptureContext {
  const CaptureContext({
    this.tags,
    this.extra,
    this.userId,
    this.title,
    this.mechanism,
  });

  final Map<String, String>? tags;
  final Map<String, Object?>? extra;
  final String? userId;
  final String? title;
  final ExceptionMechanism? mechanism;

  CaptureContext merge(CaptureContext? other) {
    if (other == null) {
      return this;
    }
    return CaptureContext(
      tags: {
        ...?tags,
        ...?other.tags,
      },
      extra: {
        ...?extra,
        ...?other.extra,
      },
      userId: other.userId ?? userId,
      title: other.title ?? title,
      mechanism: other.mechanism ?? mechanism,
    );
  }
}

/// Exception mechanism metadata for wire `ExceptionMechanismDto`.
class ExceptionMechanism {
  const ExceptionMechanism({
    this.type = 'generic',
    this.handled = true,
    this.synthetic = false,
  });

  final String type;
  final bool handled;
  final bool synthetic;

  Map<String, Object?> toWire() => {
        '__className__': 'ExceptionMechanismDto',
        'type': type.isEmpty ? 'generic' : type,
        'handled': handled,
        'synthetic': synthetic,
      };
}

/// Mutable event bag passed to [TalariaOptions.beforeSend].
class BeforeSendEvent {
  BeforeSendEvent({
    required this.message,
    required this.level,
    this.title,
    this.tags = const {},
    this.extra = const {},
    this.userId,
    this.exception,
  });

  String message;
  SeverityLevel level;
  String? title;
  Map<String, String> tags;
  Map<String, Object?> extra;
  String? userId;
  Map<String, Object?>? exception;

  String get eventType => level.toEventType();
}

/// Hint passed alongside [BeforeSendEvent].
class BeforeSendHint {
  const BeforeSendHint({
    this.originalContext,
    this.isException = false,
  });

  final CaptureContext? originalContext;
  final bool isException;
}

/// Named logger preset from init.
class LoggerPreset {
  const LoggerPreset({
    this.minLevel,
    this.tags,
  });

  final SeverityLevel? minLevel;
  final Map<String, String>? tags;
}

/// Options for [TalariaLogger] / [TalariaClient.logger].
class LoggerOptions {
  const LoggerOptions({
    this.name,
    this.tags,
    this.minLevel,
  });

  final String? name;
  final Map<String, String>? tags;
  final SeverityLevel? minLevel;
}
