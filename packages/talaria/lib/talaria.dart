/// Official Dart SDK for Talaria — exception and log capture.
library;

export 'src/capture_context.dart';
export 'src/client.dart';
export 'src/config.dart';
export 'src/context/runtime_context.dart';
export 'src/environment.dart';
export 'src/event.dart';
export 'src/http/talaria_http_client.dart';
export 'src/logger.dart';
export 'src/severity.dart';
export 'src/talaria.dart';
export 'src/tracing/breadcrumbs.dart';
export 'src/tracing/span.dart';
export 'src/tracing/trace_context.dart';
export 'src/tracing/tracer.dart' show Tracer, SpanEnrichment;
export 'src/integration/zone_integration.dart' show runZonedTalaria;
export 'src/transport/http_transport.dart' show HttpTransport;
export 'src/transport/transport.dart' show Transport, TransportException;
