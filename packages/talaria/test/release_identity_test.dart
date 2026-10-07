import 'package:talaria/src/release_identity.dart';
import 'package:test/test.dart';

void main() {
  const full = 'a8f31c2e4b6d8901234567890abcdef123456789';

  test('explicit release wins over CI', () {
    final resolved = ReleaseIdentity.resolve(
      release: '1.4.2',
      env: const {
        'GITHUB_REF_NAME': 'main',
        'GITHUB_SHA': full,
        'GITHUB_REF_TYPE': 'branch',
      },
    );
    expect(resolved.release, '1.4.2');
    expect(resolved.commitSha, isNull);
    expect(resolved.releaseRefKind, isNull);
  });

  test('GitHub Actions fills ref@shortsha', () {
    final resolved = ReleaseIdentity.resolve(
      env: const {
        'GITHUB_REF_NAME': 'feature/new-checkout',
        'GITHUB_SHA': 'f32a991e4b6d8901234567890abcdef123456789',
        'GITHUB_REF_TYPE': 'branch',
      },
    );
    expect(resolved.release, 'feature/new-checkout@f32a991');
    expect(resolved.commitSha, 'f32a991e4b6d8901234567890abcdef123456789');
    expect(resolved.releaseRefKind, 'branch');
  });

  test('GitLab tag uses the tag name', () {
    final resolved = ReleaseIdentity.resolve(
      env: const {
        'CI_COMMIT_REF_NAME': 'v1.4.2',
        'CI_COMMIT_SHA': full,
        'CI_COMMIT_TAG': 'v1.4.2',
      },
    );
    expect(resolved.release, 'v1.4.2@a8f31c2');
    expect(resolved.releaseRefKind, 'tag');
  });
}
