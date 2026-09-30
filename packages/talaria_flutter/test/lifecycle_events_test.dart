import 'package:flutter/widgets.dart';
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

  Future<FakeTransport> start(
    WidgetTester tester, {
    bool enableAnalytics = true,
    bool trackLifecycleEvents = true,
  }) async {
    final transport = FakeTransport();
    final options = TalariaOptions(
      dsn: 'https://api.example.com',
      apiKey: 'tal_live_test_key_for_unit_tests',
      environment: 'development',
      defaultIntegrations: false,
      flushIntervalMs: 0,
    );
    if (enableAnalytics) {
      options.applySdkDocument({
        'schemaVersion': 1,
        'active': true,
        'analytics': {'enabled': true},
      });
    }
    await TalariaFlutter.init(
      options,
      transport: transport,
      trackLifecycleEvents: trackLifecycleEvents,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    return transport;
  }

  Future<List<String>> trackedNames(
    WidgetTester tester,
    FakeTransport transport,
  ) async {
    await Talaria.flush();
    await tester.pump();
    return [
      for (final batch in transport.analyticsBatches)
        for (final event in batch) event.name,
    ];
  }

  Future<void> setState(
    WidgetTester tester,
    AppLifecycleState state,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(state);
    await tester.pump();
  }

  testWidgets('foreground and background emit the stable event names',
      (tester) async {
    final transport = await start(tester);

    await setState(tester, AppLifecycleState.resumed);
    await setState(tester, AppLifecycleState.paused);

    expect(
      await trackedNames(tester, transport),
      containsAllInOrder([
        'Application Opened',
        'Application Backgrounded',
      ]),
    );
  });

  testWidgets('names are exported as constants', (tester) async {
    expect(TalariaLifecycleEvents.opened, 'Application Opened');
    expect(TalariaLifecycleEvents.backgrounded, 'Application Backgrounded');
  });

  testWidgets('repeated resumed does not re-open', (tester) async {
    final transport = await start(tester);

    await setState(tester, AppLifecycleState.resumed);
    await setState(tester, AppLifecycleState.inactive);
    await setState(tester, AppLifecycleState.resumed);

    final names = await trackedNames(tester, transport);
    expect(names.where((n) => n == 'Application Opened'), hasLength(1));
    expect(names, isNot(contains('Application Backgrounded')));
  });

  testWidgets('hidden then paused reports one backgrounded', (tester) async {
    final transport = await start(tester);

    await setState(tester, AppLifecycleState.resumed);
    await setState(tester, AppLifecycleState.hidden);
    await setState(tester, AppLifecycleState.paused);

    final names = await trackedNames(tester, transport);
    expect(names.where((n) => n == 'Application Backgrounded'), hasLength(1));
  });

  testWidgets('a foreground return opens again', (tester) async {
    final transport = await start(tester);

    await setState(tester, AppLifecycleState.resumed);
    await setState(tester, AppLifecycleState.paused);
    await setState(tester, AppLifecycleState.resumed);

    final names = await trackedNames(tester, transport);
    expect(names.where((n) => n == 'Application Opened'), hasLength(2));
  });

  testWidgets('nothing is tracked while analytics is off', (tester) async {
    final transport = await start(tester, enableAnalytics: false);

    await setState(tester, AppLifecycleState.resumed);
    await setState(tester, AppLifecycleState.paused);

    expect(await trackedNames(tester, transport), isEmpty);
  });

  testWidgets('opting in mid-session starts tracking', (tester) async {
    final transport = await start(tester, enableAnalytics: false);

    await setState(tester, AppLifecycleState.resumed);
    Talaria.getClient()!.analytics.optIn();
    await setState(tester, AppLifecycleState.paused);
    await setState(tester, AppLifecycleState.resumed);

    expect(
      await trackedNames(tester, transport),
      contains('Application Opened'),
    );
  });

  testWidgets('trackLifecycleEvents: false keeps the tags without the events',
      (tester) async {
    final transport = await start(tester, trackLifecycleEvents: false);

    await setState(tester, AppLifecycleState.resumed);
    await setState(tester, AppLifecycleState.paused);

    expect(await trackedNames(tester, transport), isEmpty);
  });
}
