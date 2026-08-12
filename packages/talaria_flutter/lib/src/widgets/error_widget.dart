import 'package:flutter/widgets.dart';
import 'package:talaria/talaria.dart';

/// Reports build failures to Talaria, then falls back to [ErrorWidget.builder].
Widget Function(FlutterErrorDetails details) talariaErrorWidgetBuilder({
  TalariaClient? client,
  Widget Function(FlutterErrorDetails details)? fallback,
}) {
  final previous = fallback ?? ErrorWidget.builder;
  return (FlutterErrorDetails details) {
    final c = client ?? Talaria.getClient();
    // ignore: discarded_futures
    c?.captureException(
      details.exception,
      stackTrace: details.stack,
      context: const CaptureContext(
        mechanism: ExceptionMechanism(
          type: 'error_widget',
          handled: true,
        ),
        tags: {'source': 'error_widget'},
      ),
    );
    return previous(details);
  };
}
