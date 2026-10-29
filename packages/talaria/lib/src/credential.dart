import 'dart:convert';
import 'dart:developer' as developer;

/// A `tal_pk_`, `tal_sk_`, or `tal_mon_` credential.
///
/// Grammar and CRC32 base62 checksum match naming-audit §5.1. The checksum
/// alphabet is `0-9A-Za-z`.
class TalariaCredential {
  TalariaCredential._({
    required this.value,
    required this.kind,
    required this.env,
    required this.cell,
    required this.random,
    required this.checksum,
  });

  /// Publishable key, secret key, or monitor token (`pk`, `sk`, `mon`).
  final String kind;

  /// `prod`, `stg`, `test`, or `dev`. Null for a monitor token.
  final String? env;

  final String cell;
  final String random;
  final String checksum;

  /// The credential exactly as parsed, with surrounding space removed.
  final String value;

  static const alphabet =
      '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';

  static final apiKeyPattern = RegExp(
    r'^tal_(pk|sk)_(prod|stg|test|dev)_([a-z][a-z0-9]*(?:-[a-z0-9]+)*)_([A-Za-z0-9]{43})([A-Za-z0-9]{6})$',
  );

  static final monitorTokenPattern = RegExp(
    r'^tal_mon_([a-z][a-z0-9]*(?:-[a-z0-9]+)*)_([A-Za-z0-9]{43})([A-Za-z0-9]{6})$',
  );

  bool get isPublishable => kind == 'pk';
  bool get isSecret => kind == 'sk';
  bool get isMonitor => kind == 'mon';
  bool get isSelfCell => cell == 'self';

  /// `https://ingest-<cell>.newtalaria.com`.
  String get derivedIngestUrl => 'https://ingest-$cell.newtalaria.com';

  /// How many times a server SDK has warned about a publishable key.
  static int publishableServerWarnings = 0;

  static void resetPublishableServerWarnings() {
    publishableServerWarnings = 0;
  }

  /// One warning per process when a Dart VM / server SDK is given a `tal_pk_` key.
  static void warnIfPublishableOnServer(
    TalariaCredential credential, {
    required String platform,
  }) {
    if (platform == 'flutter' || !credential.isPublishable) return;
    if (publishableServerWarnings > 0) return;
    publishableServerWarnings++;
    developer.log(
      '[Talaria] tal_pk_ key on a server SDK. Ingest works, but '
      'releases, flag definitions, and monitor check-ins need a tal_sk_ key.',
      name: 'talaria',
    );
  }

  static TalariaCredential parse(String raw) {
    final value = raw.trim();
    final api = apiKeyPattern.firstMatch(value);
    if (api != null) {
      return _checked(
        value: value,
        kind: api.group(1)!,
        env: api.group(2)!,
        cell: api.group(3)!,
        random: api.group(4)!,
        checksum: api.group(5)!,
      );
    }
    final monitor = monitorTokenPattern.firstMatch(value);
    if (monitor != null) {
      return _checked(
        value: value,
        kind: 'mon',
        env: null,
        cell: monitor.group(1)!,
        random: monitor.group(2)!,
        checksum: monitor.group(3)!,
      );
    }
    throw ArgumentError(
      'Talaria apiKey must match tal_pk_|tal_sk_<env>_<cell>_<43 base62><6 CRC32> '
      'or tal_mon_<cell>_<43 base62><6 CRC32>.',
    );
  }

  static TalariaCredential _checked({
    required String value,
    required String kind,
    required String? env,
    required String cell,
    required String random,
    required String checksum,
  }) {
    if (cell.length < 2 || cell.length > 24) {
      throw ArgumentError(
        'Talaria cell id must be 2–24 characters (got "$cell").',
      );
    }
    final signed = value.substring(0, value.length - checksum.length);
    final expected = crc32Base62(signed);
    if (expected != checksum) {
      throw ArgumentError(
        'Talaria apiKey checksum does not match. The key is truncated or mistyped.',
      );
    }
    return TalariaCredential._(
      value: value,
      kind: kind,
      env: env,
      cell: cell,
      random: random,
      checksum: checksum,
    );
  }

  /// Builds a credential whose checksum is valid. For tests and local tooling.
  static String mint({
    String kind = 'sk',
    String env = 'test',
    String cell = 'nz1',
    String random = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefg',
  }) {
    if (random.length != 43) {
      throw ArgumentError(
          'Credential random body must be 43 base62 characters.');
    }
    final prefix = kind == 'mon'
        ? 'tal_mon_${cell}_$random'
        : 'tal_${kind}_${env}_${cell}_$random';
    return '$prefix${crc32Base62(prefix)}';
  }

  /// IEEE CRC32 of [input], written as 6 base62 characters, alphabet `0-9A-Za-z`.
  static String crc32Base62(String input) {
    var value = crc32(utf8.encode(input));
    final chars = List<String>.filled(6, '0');
    for (var i = 5; i >= 0; i--) {
      chars[i] = alphabet[value % 62];
      value ~/= 62;
    }
    return chars.join();
  }

  /// CRC-32/ISO-HDLC (IEEE), init `0xFFFFFFFF`, xorout `0xFFFFFFFF`.
  static int crc32(List<int> bytes) {
    var crc = 0xFFFFFFFF;
    for (final byte in bytes) {
      crc ^= byte & 0xFF;
      for (var i = 0; i < 8; i++) {
        final mask = -(crc & 1) & 0xEDB88320;
        crc = (crc >> 1) ^ mask;
      }
      crc &= 0xFFFFFFFF;
    }
    return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }
}
