import 'package:talaria/src/transport/fake_transport.dart';
import 'package:talaria/talaria.dart';
import 'package:test/test.dart';

void main() {
  test('CRC32 of 123456789 is the IEEE check value', () {
    expect(
      TalariaCredential.crc32('123456789'.codeUnits).toRadixString(16),
      'cbf43926',
    );
  });

  test('minted pk and sk keys round-trip', () {
    final sk = TalariaCredential.parse(TalariaCredential.mint());
    expect(sk.kind, 'sk');
    expect(sk.env, 'test');
    expect(sk.cell, 'nz1');
    expect(sk.derivedIngestUrl, 'https://ingest-nz1.newtalaria.com');

    final pk = TalariaCredential.parse(
        TalariaCredential.mint(kind: 'pk', env: 'prod', cell: 'eu1-k7m2p9'));
    expect(pk.isPublishable, isTrue);
    expect(pk.env, 'prod');
    expect(pk.cell, 'eu1-k7m2p9');
    expect(pk.derivedIngestUrl, 'https://ingest-eu1-k7m2p9.newtalaria.com');
  });

  test('monitor tokens parse and are refused as an SDK apiKey', () {
    final token = TalariaCredential.parse(TalariaCredential.mint(kind: 'mon'));
    expect(token.isMonitor, isTrue);
    expect(token.env, isNull);
    expect(
      () => TalariaOptions(apiKey: token.value),
      throwsArgumentError,
    );
  });

  test('a bad checksum fails fast', () {
    final key = TalariaCredential.mint();
    final broken = '${key.substring(0, key.length - 1)}0';
    expect(() => TalariaCredential.parse(broken), throwsArgumentError);
  });

  test('class-less and tal_live_ keys fail the grammar', () {
    expect(
      () => TalariaCredential.parse(
        'tal_prod_nz1_0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefg000000',
      ),
      throwsArgumentError,
    );
    expect(
      () => TalariaCredential.parse(
        'tal_live_nz1_0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefg000000',
      ),
      throwsArgumentError,
    );
  });

  test('url is derived from the cell unless overridden', () {
    final key = TalariaCredential.mint(kind: 'sk', env: 'prod', cell: 'nz1');
    expect(
        TalariaOptions(apiKey: key).url, 'https://ingest-nz1.newtalaria.com');
    expect(
      TalariaOptions(apiKey: key, url: 'https://ingest.example.test/').url,
      'https://ingest.example.test',
    );
  });

  test('a self cell fails fast without TALARIA_URL or url', () {
    final key = TalariaCredential.mint(cell: 'self');
    expect(() => TalariaOptions(apiKey: key), throwsArgumentError);
    expect(
      TalariaOptions(apiKey: key, url: 'http://localhost:8080').url,
      'http://localhost:8080',
    );
  });

  test('a server SDK warns once on a publishable key', () {
    TalariaCredential.resetPublishableServerWarnings();
    final pk = TalariaCredential.mint(kind: 'pk');
    final transport = FakeTransport();
    TalariaClient(
      TalariaOptions(
          apiKey: pk, defaultIntegrations: false, flushIntervalMs: 0),
      transport: transport,
    );
    TalariaClient(
      TalariaOptions(
          apiKey: pk, defaultIntegrations: false, flushIntervalMs: 0),
      transport: transport,
    );
    expect(TalariaCredential.publishableServerWarnings, 1);
  });
}
