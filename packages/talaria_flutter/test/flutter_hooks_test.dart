import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:talaria/src/transport/fake_transport.dart';
import 'package:talaria_flutter/talaria_flutter.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    await TalariaFlutter.close();
  });

  testWidgets('navigator observer sets route tags', (tester) async {
    final transport = FakeTransport();
    await TalariaFlutter.init(
      TalariaOptions(
        dsn: 'https://api.example.com',
        apiKey: 'tal_live_test_key_for_unit_tests',
        environment: 'development',
        defaultIntegrations: false,
        flushIntervalMs: 0,
      ),
      transport: transport,
      observeLifecycle: false,
    );

    final observer = TalariaNavigatorObserver();
    final navigatorKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        navigatorObservers: [observer],
        routes: {
          '/': (_) => const Scaffold(body: Text('home')),
          '/checkout': (_) => const Scaffold(body: Text('checkout')),
        },
      ),
    );

    expect(observer.currentRoute, '/');

    navigatorKey.currentState!.pushNamed('/checkout');
    await tester.pumpAndSettle();

    expect(observer.currentRoute, '/checkout');
    expect(Talaria.getClient(), isNotNull);
  });

  testWidgets('navigator observer starts a transaction per route',
      (tester) async {
    final transport = FakeTransport();
    await TalariaFlutter.init(
      TalariaOptions(
        dsn: 'https://api.example.com',
        apiKey: 'tal_live_test_key_for_unit_tests',
        environment: 'development',
        defaultIntegrations: false,
        flushIntervalMs: 0,
        tracesSampleRate: 1.0,
      ),
      transport: transport,
      observeLifecycle: false,
    );

    final observer = TalariaNavigatorObserver();
    final navigatorKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        navigatorObservers: [observer],
        routes: {
          '/': (_) => const Scaffold(body: Text('home')),
          '/checkout': (_) => const Scaffold(body: Text('checkout')),
        },
      ),
    );

    navigatorKey.currentState!.pushNamed('/checkout');
    await tester.pumpAndSettle();
    await Talaria.flush();

    final finished = transport.spanBatches.expand((b) => b).toList();
    expect(finished, isNotEmpty);
    expect(finished.first.name, '/');
    expect(observer.currentRoute, '/checkout');
    expect(RuntimeContext.url, '/checkout');
  });

  testWidgets(
      'navigator observer finishes the route span without a second push',
      (tester) async {
    final transport = FakeTransport();
    await TalariaFlutter.init(
      TalariaOptions(
        dsn: 'https://api.example.com',
        apiKey: 'tal_live_test_key_for_unit_tests',
        environment: 'development',
        defaultIntegrations: false,
        flushIntervalMs: 0,
        tracesSampleRate: 1.0,
      ),
      transport: transport,
      observeLifecycle: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [TalariaNavigatorObserver()],
        home: const Scaffold(body: Text('home')),
      ),
    );
    await tester.pump();
    await Talaria.flush();

    final finished = transport.spanBatches.expand((b) => b).toList();
    expect(finished, isNotEmpty);
    expect(finished.first.name, '/');
    expect(finished.first.kind, SpanKind.internal);
  });

  testWidgets('setScreen starts a short INTERNAL span', (tester) async {
    final transport = FakeTransport();
    await TalariaFlutter.init(
      TalariaOptions(
        dsn: 'https://api.example.com',
        apiKey: 'tal_live_test_key_for_unit_tests',
        environment: 'development',
        defaultIntegrations: false,
        flushIntervalMs: 0,
        tracesSampleRate: 1.0,
      ),
      transport: transport,
      observeLifecycle: false,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    TalariaFlutter.setScreen('/lab');
    TalariaFlutter.setScreen('/cart');
    await Talaria.flush();

    final finished = transport.spanBatches.expand((b) => b).toList();
    expect(finished.map((s) => s.name), contains('/lab'));
    expect(
      finished.firstWhere((s) => s.name == '/lab').kind,
      SpanKind.internal,
    );
    expect(RuntimeContext.url, '/cart');
  });

  testWidgets('widget build errors are captured once as error_widget',
      (tester) async {
    final transport = FakeTransport();
    await TalariaFlutter.init(
      TalariaOptions(
        dsn: 'https://api.example.com',
        apiKey: 'tal_live_test_key_for_unit_tests',
        environment: 'development',
        defaultIntegrations: false,
        flushIntervalMs: 0,
      ),
      transport: transport,
      observeLifecycle: false,
    );
    final previousBuilder = ErrorWidget.builder;
    ErrorWidget.builder = talariaErrorWidgetBuilder();
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (_) => throw FlutterError('Harbor lab ErrorWidget'),
          ),
        ),
      );
      tester.takeException();
      await tester.pump();
      await Talaria.flush();
      await tester.idle();

      final events = transport.batches.expand((b) => b).toList();
      expect(events, hasLength(1));
      final exception = events.single.exception!;
      final values = exception['values'] as List;
      final mechanism = (values.first as Map)['mechanism'] as Map;
      expect(mechanism['type'], 'error_widget');
    } finally {
      ErrorWidget.builder = previousBuilder;
    }
  });

  test('isWidgetBuildError detects widgets library failures', () {
    expect(
      TalariaFlutter.isWidgetBuildError(
        FlutterErrorDetails(
          exception: FlutterError('broken'),
          library: 'widgets library',
        ),
      ),
      isTrue,
    );
    expect(
      TalariaFlutter.isWidgetBuildError(
        FlutterErrorDetails(
          exception: FlutterError('other'),
          library: 'rendering library',
        ),
      ),
      isFalse,
    );
  });

  testWidgets('init enriches runtime extra with locale and os', (tester) async {
    final transport = FakeTransport();
    await TalariaFlutter.init(
      TalariaOptions(
        dsn: 'https://api.example.com',
        apiKey: 'tal_live_test_key_for_unit_tests',
        environment: 'development',
        defaultIntegrations: false,
        flushIntervalMs: 0,
      ),
      transport: transport,
      observeLifecycle: false,
    );

    await Talaria.captureException(StateError('runtime extra'));
    await Talaria.flush();

    final extra = transport.batches.expand((b) => b).single.extraJson;
    expect(extra, isNotNull);
    expect(extra, contains('locale'));
    expect(extra, contains('os'));
  });

  testWidgets('init installs FlutterError hook and sets flutter platform',
      (tester) async {
    final transport = FakeTransport();
    final client = await TalariaFlutter.init(
      TalariaOptions(
        dsn: 'https://api.example.com',
        apiKey: 'tal_live_test_key_for_unit_tests',
        environment: 'development',
        defaultIntegrations: false,
        flushIntervalMs: 0,
      ),
      transport: transport,
      observeLifecycle: false,
    );

    expect(FlutterError.onError, isNotNull);
    expect(client.platformOverride, 'flutter');

    await client.captureException(
      StateError('from flutter'),
      stackTrace: StackTrace.current,
    );
    await Talaria.flush();

    expect(transport.batches, isNotEmpty);
    expect(transport.batches.first.single.message, contains('from flutter'));
    expect(transport.batches.first.single.platform, 'flutter');
  });

  testWidgets('navigator observer emits \$screen when analytics is on',
      (tester) async {
    final transport = FakeTransport();
    await TalariaFlutter.init(
      TalariaOptions(
        dsn: 'https://api.example.com',
        apiKey: 'tal_live_test_key_for_unit_tests',
        environment: 'development',
        defaultIntegrations: false,
        flushIntervalMs: 0,
        enableAnalytics: true,
        storage: MemoryTalariaStorage(),
      ),
      transport: transport,
      observeLifecycle: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [TalariaNavigatorObserver()],
        home: const Scaffold(body: Text('home')),
      ),
    );
    await tester.pump();
    await Talaria.flush();

    final events = transport.analyticsBatches.expand((b) => b).toList();
    expect(events, isNotEmpty);
    expect(events.first.name, r'$screen');
    expect(events.first.kind, AnalyticsEventKind.screen);
    expect(events.first.path, '/');
    expect(events.first.anonymousId, isNotEmpty);
  });

  test('SharedPreferences storage persists anonymousId', () async {
    SharedPreferences.setMockInitialValues({});
    final first = await SharedPreferencesTalariaStorage.create();
    await first.write(Identity.anonymousIdKey, 'anon-persist');

    final second = await SharedPreferencesTalariaStorage.create();
    expect(second.read(Identity.anonymousIdKey), 'anon-persist');
  });
}
