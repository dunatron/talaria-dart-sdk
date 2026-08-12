/// Smoke-test script: builds a real ingestBatch payload and optionally POSTs it.
///
/// ```bash
/// cd packages/talaria
/// dart run tool/smoke_ingest.dart
/// TALARIA_DSN=https://api… TALARIA_API_KEY=tal_live_… dart run tool/smoke_ingest.dart --live
/// ```
library;

import 'dart:convert';
import 'dart:io';

import 'package:talaria/src/transport/fake_transport.dart';
import 'package:talaria/talaria.dart';

Future<void> main(List<String> args) async {
  final live = args.contains('--live');
  final dsn = Platform.environment['TALARIA_DSN'] ?? 'https://api.newtalaria.com';
  final apiKey = Platform.environment['TALARIA_API_KEY'];

  if (live) {
    if (apiKey == null || !apiKey.startsWith('tal_live_')) {
      stderr.writeln(
        'For --live, set TALARIA_API_KEY to a project key (tal_live_…).',
      );
      exitCode = 1;
      return;
    }
  }

  final fake = FakeTransport();
  final client = TalariaClient(
    TalariaOptions(
      dsn: dsn,
      apiKey: apiKey ?? 'tal_live_smoke_test_placeholder_key_xxxxxx',
      environment: 'development',
      release: '0.1.0+smoke',
      defaultIntegrations: false,
      flushIntervalMs: 0,
      minLevel: SeverityLevel.debug,
    ),
    transport: live ? null : fake,
  );

  try {
    throw StateError('Dart SDK smoke test exception');
  } catch (e, st) {
    await client.captureException(
      e,
      stackTrace: st,
      context: const CaptureContext(
        tags: {'smoke': 'true', 'sdk': 'talaria'},
        extra: {'purpose': 'smoke_ingest'},
      ),
    );
  }

  await client.warning(
    'Dart SDK smoke test warning',
    context: const CaptureContext(tags: {'smoke': 'true'}),
  );

  await client.flush();

  if (!live) {
    if (fake.batches.isEmpty) {
      stderr.writeln('FAIL: no batches enqueued');
      exitCode = 1;
      await client.close();
      return;
    }
    final wire = {
      'input': {
        '__className__': 'IngestEventBatchInput',
        'events': [
          for (final e in fake.batches.expand((b) => b)) e.toWire(),
        ],
      },
    };
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(wire));
    stdout.writeln(
      'OK: dry-run payload looks valid '
      '(${fake.batches.expand((b) => b).length} events). '
      'Re-run with --live and TALARIA_DSN / TALARIA_API_KEY to POST.',
    );
  } else {
    stdout.writeln('OK: live flush completed against $dsn');
  }

  await client.close();
}
