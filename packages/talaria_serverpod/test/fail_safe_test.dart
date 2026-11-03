import 'dart:io';

import 'package:serverpod/serverpod.dart';
import 'package:talaria/src/transport/fake_transport.dart';
import 'package:talaria_serverpod/talaria_serverpod.dart';
import 'package:test/test.dart';

/// D19: a bad key never stops a Serverpod process. Talaria is just disabled.
void main() {
  late List<String> warnings;

  setUp(() {
    FailSafe.reset();
    warnings = [];
    FailSafe.sink = warnings.add;
  });

  tearDown(() async {
    FailSafe.sink = null;
    await Talaria.reset();
    TalariaServerpod.clearSessionUsersForTest();
  });

  test('flags before init return defaults instead of throwing', () async {
    expect(await TalariaServerpodFlags.boolVariation('f', true), isTrue);
    expect(await TalariaServerpodFlags.stringVariation('s', 'd'), 'd');
    expect(await TalariaServerpodFlags.jsonVariation('j', 1), 1);
    await TalariaServerpodFlags.setContext(userId: 'u');
    await TalariaServerpodFlags.ensureLocalDefinitions();
  });

  for (final entry in {
    'no key': '',
    'a malformed key': 'tal_live_g2WhG4abcdefghijklmnopqrstuvwxyz0123456789',
    'a monitor token': TalariaCredential.mint(kind: 'mon'),
  }.entries) {
    test('${entry.key}: init never throws and patches nothing', () async {
      final previousOverrides = HttpOverrides.current;
      final transport = FakeTransport();
      final client = await TalariaServerpod.init(
        TalariaOptions(apiKey: entry.value, flushIntervalMs: 0),
        transport: transport,
      );
      expect(client.isEnabled, isFalse);
      expect(HttpOverrides.current, same(previousOverrides));

      TalariaServerpod.handleExceptionEvent(
        ExceptionEvent(StateError('app bug'), StackTrace.current),
      );
      expect(await TalariaServerpodFlags.boolVariation('f', false), isFalse);
      await Future<void>.delayed(Duration.zero);
      await Talaria.flush();

      expect(transport.batches, isEmpty);
      expect(warnings, hasLength(1), reason: warnings.join('\n'));
      expect(warnings.single, contains('Talaria is disabled'));
    });
  }

  test('a failing transport never reaches the diagnostic handler', () async {
    await TalariaServerpod.init(
      TalariaOptions(
        url: 'https://api.example.com',
        apiKey:
            'tal_sk_test_nz1_0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefg3B299S',
        defaultIntegrations: false,
        flushIntervalMs: 0,
      ),
      transport: _ThrowingTransport(),
    );
    expect(
      () => TalariaServerpod.handleExceptionEvent(
        ExceptionEvent(StateError('app bug'), StackTrace.current),
      ),
      returnsNormally,
    );
    await Future<void>.delayed(Duration.zero);
    await Talaria.flush();
    await Talaria.flush();
  });
}

class _ThrowingTransport extends FakeTransport {
  @override
  Future<void> sendBatch(List<Event> events) async =>
      throw const SocketException('Connection refused');
}
