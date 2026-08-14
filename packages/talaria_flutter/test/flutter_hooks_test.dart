import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:talaria/src/transport/fake_transport.dart';
import 'package:talaria_flutter/talaria_flutter.dart';

void main() {
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
}
