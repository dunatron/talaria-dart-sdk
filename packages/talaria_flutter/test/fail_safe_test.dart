import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:talaria/src/transport/fake_transport.dart';
import 'package:talaria_flutter/talaria_flutter.dart';

/// D19: a bad key never breaks a Flutter app. Talaria is just switched off.
void main() {
  const pk =
      'tal_pk_test_nz1_0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefg3j7IsA';
  late List<String> warnings;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FailSafe.reset();
    warnings = [];
    FailSafe.sink = warnings.add;
  });

  tearDown(() async {
    FailSafe.sink = null;
    await TalariaFlutter.close();
  });

  final badKeys = <String, String>{
    'no key': '',
    'a malformed key': 'tal_live_g2WhG4abcdefghijklmnopqrstuvwxyz0123456789',
    'a wrong checksum': '${pk.substring(0, pk.length - 1)}B',
    'a secret key': TalariaCredential.mint(kind: 'sk'),
    'a monitor token': TalariaCredential.mint(kind: 'mon'),
  };

  for (final entry in badKeys.entries) {
    test('${entry.key}: init never throws and installs no hooks', () async {
      final previousFlutter = FlutterError.onError;
      final previousPlatform = PlatformDispatcher.instance.onError;
      final transport = FakeTransport();

      final client = await TalariaFlutter.init(
        TalariaOptions(apiKey: entry.value, flushIntervalMs: 0),
        transport: transport,
      );

      expect(client.isEnabled, isFalse);
      expect(Talaria.isEnabled, isFalse);
      expect(FlutterError.onError, same(previousFlutter));
      expect(PlatformDispatcher.instance.onError, same(previousPlatform));

      await Talaria.captureException(StateError('ignored'));
      await Talaria.analytics.track('ignored', userId: 'u');
      TalariaFlutter.setScreen('home');
      await Talaria.flush();
      expect(transport.batches, isEmpty);
      expect(transport.analyticsBatches, isEmpty);

      expect(warnings, hasLength(1), reason: warnings.join('\n'));
      expect(warnings.single, contains('Talaria is disabled'));
      if (entry.value.length > 8) {
        expect(warnings.single, isNot(contains(entry.value.substring(0, 9))));
      }
    });
  }

  test('installErrorHooks is a no-op for a disabled client', () {
    final previous = FlutterError.onError;
    TalariaFlutter.installErrorHooks(
      TalariaClient(TalariaOptions(apiKey: 'nope')),
    );
    expect(FlutterError.onError, same(previous));
  });

  testWidgets('runZonedApp still runs the app with a bad key', (tester) async {
    final previousBuilder = ErrorWidget.builder;
    await tester.runAsync(
      () => TalariaFlutter.runZonedApp(
        TalariaOptions(apiKey: 'tal_live_broken'),
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Text('app is up'),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('app is up'), findsOneWidget);
    expect(Talaria.isEnabled, isFalse);
    expect(ErrorWidget.builder, same(previousBuilder));
    expect(warnings, hasLength(1));
  });

  test('hooks swallow a failing capture and still call the previous handler',
      () async {
    final seen = <FlutterErrorDetails>[];
    final original = FlutterError.onError;
    FlutterError.onError = seen.add;
    try {
      final client = TalariaClient(
        TalariaOptions(
          apiKey: pk,
          url: 'https://api.example.com',
          defaultIntegrations: false,
          flushIntervalMs: 0,
        ),
        transport: _ThrowingTransport(),
      );
      TalariaFlutter.installErrorHooks(client);
      final details = FlutterErrorDetails(
        exception: StateError('app bug'),
        library: 'test library',
      );
      expect(() => FlutterError.onError!(details), returnsNormally);
      await client.flush();
      expect(seen, [details]);
      await TalariaFlutter.close();
    } finally {
      FlutterError.onError = original;
    }
  });
}

class _ThrowingTransport extends FakeTransport {
  @override
  Future<void> sendBatch(List<Event> events) async =>
      throw StateError('network down');
}
