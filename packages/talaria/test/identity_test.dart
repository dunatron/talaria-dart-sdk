import 'package:talaria/talaria.dart';
import 'package:test/test.dart';

void main() {
  test('generates and persists anonymousId', () {
    final storage = MemoryTalariaStorage();
    final first = Identity(storage: storage);
    expect(first.anonymousId, isNotEmpty);
    expect(storage.read(Identity.anonymousIdKey), first.anonymousId);

    final second = Identity(storage: storage);
    expect(second.anonymousId, first.anonymousId);
    expect(second.sessionId, first.sessionId);
  });

  test('rotates session after 30 minutes of inactivity', () {
    var now = DateTime.utc(2026, 1, 1, 12, 0, 0);
    final identity = Identity(
      storage: MemoryTalariaStorage(),
      clock: () => now,
    );
    final first = identity.touch();

    now = now.add(const Duration(minutes: 29));
    expect(identity.sessionId, first);

    now = now.add(const Duration(minutes: 2));
    final rotated = identity.touch();
    expect(rotated, isNot(first));
    expect(identity.sessionId, rotated);
    expect(identity.anonymousId, isNotEmpty);
  });

  test('rotates session at midnight UTC', () {
    var now = DateTime.utc(2026, 1, 1, 23, 50, 0);
    final identity = Identity(
      storage: MemoryTalariaStorage(),
      clock: () => now,
    );
    final first = identity.touch();

    now = DateTime.utc(2026, 1, 2, 0, 1, 0);
    expect(identity.touch(), isNot(first));
  });

  test('reset mints a new anonymousId and session', () async {
    final identity = Identity(storage: MemoryTalariaStorage());
    final anon = identity.anonymousId;
    final session = identity.sessionId;
    await identity.reset();
    expect(identity.anonymousId, isNot(anon));
    expect(identity.sessionId, isNot(session));
  });

  test('captures first-touch UTM and ignores later values', () {
    final identity = Identity(storage: MemoryTalariaStorage());
    identity.captureUtmFromUrl(
      'https://example.com/?utm_source=google&utm_medium=cpc',
    );
    identity.captureUtmFromUrl(
      'https://example.com/?utm_source=twitter&utm_medium=social',
    );
    expect(identity.firstTouchUtm?.source, 'google');
    expect(identity.firstTouchUtm?.medium, 'cpc');
  });
}
