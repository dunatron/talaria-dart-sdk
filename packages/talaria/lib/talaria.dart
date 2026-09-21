/// Official Dart SDK for Talaria — exception and log capture.
library;

export 'src/analytics/analytics.dart' show TalariaAnalytics;
export 'src/analytics/analytics_event.dart'
    show
        AnalyticsEvent,
        AnalyticsEventKind,
        AnalyticsEventNames,
        AnalyticsPageContext,
        AnalyticsContextProvider;
export 'src/capture_context.dart';
export 'src/client.dart';
export 'src/config.dart';
export 'src/context/runtime_context.dart';
export 'src/environment.dart';
export 'src/event.dart';
export 'src/http/talaria_http_client.dart';
export 'src/identity/identity.dart' show Identity;
export 'src/identity/storage.dart' show TalariaStorage, MemoryTalariaStorage;
export 'src/identity/utm.dart' show Utm;
export 'src/logger.dart';
export 'src/severity.dart';
export 'src/talaria.dart';
export 'src/tracing/breadcrumbs.dart';
export 'src/tracing/db_span.dart';
export 'src/tracing/span.dart';
export 'src/tracing/span_scope.dart';
export 'src/tracing/sql_sanitizer.dart';
export 'src/tracing/trace_context.dart';
export 'src/tracing/tracer.dart' show Tracer, SpanEnrichment;
export 'src/integration/zone_integration.dart' show runZonedTalaria;
export 'src/transport/http_transport.dart' show HttpTransport;
export 'src/transport/ingest_error.dart' show IngestError, IngestSignal;
export 'src/transport/transport.dart' show Transport, TransportException;
