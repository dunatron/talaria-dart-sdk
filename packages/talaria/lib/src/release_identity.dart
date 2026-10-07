import 'release_env_stub.dart'
    if (dart.library.io) 'release_env_io.dart';

/// A resolved `<ref>@<shortsha>` plus the full commit SHA.
class ReleaseIdentity {
  const ReleaseIdentity({this.release, this.commitSha, this.releaseRefKind});

  final String? release;
  final String? commitSha;

  /// `branch`, `tag`, or null.
  final String? releaseRefKind;

  static const definedRelease = String.fromEnvironment('TALARIA_RELEASE');
  static const definedCommitSha = String.fromEnvironment('TALARIA_COMMIT_SHA');

  /// Explicit values win. `--dart-define` is next. CI env fills both only when
  /// release and commit SHA are still empty.
  static ReleaseIdentity resolve({
    String? release,
    String? commitSha,
    Map<String, String>? env,
  }) {
    final variables = env ?? releaseEnvironment();
    final explicitRelease = _nonEmpty(release) ??
        _nonEmpty(definedRelease) ??
        _nonEmpty(variables['TALARIA_RELEASE']);
    final explicitSha = _nonEmpty(commitSha) ??
        _nonEmpty(definedCommitSha) ??
        _nonEmpty(variables['TALARIA_COMMIT_SHA']);
    final ci = _fromCi(variables);

    if (explicitRelease != null || explicitSha != null) {
      final matchesCi = explicitRelease != null &&
          ci.release != null &&
          explicitRelease == ci.release;
      return ReleaseIdentity(
        release: explicitRelease,
        commitSha: explicitSha,
        releaseRefKind: matchesCi ? ci.releaseRefKind : null,
      );
    }
    return ci;
  }

  static ReleaseIdentity _fromCi(Map<String, String> env) {
    final githubRef = _nonEmpty(env['GITHUB_REF_NAME']);
    final githubSha = _nonEmpty(env['GITHUB_SHA']);
    if (githubRef != null && githubSha != null && githubSha.length >= 7) {
      final type = _nonEmpty(env['GITHUB_REF_TYPE']);
      final kind = type == 'tag' || type == 'branch' ? type : null;
      return ReleaseIdentity(
        release: '$githubRef@${githubSha.substring(0, 7)}',
        commitSha: githubSha,
        releaseRefKind: kind,
      );
    }

    final gitlabRef = _nonEmpty(env['CI_COMMIT_REF_NAME']);
    final gitlabSha = _nonEmpty(env['CI_COMMIT_SHA']);
    if (gitlabRef != null && gitlabSha != null && gitlabSha.length >= 7) {
      final tag = _nonEmpty(env['CI_COMMIT_TAG']);
      return ReleaseIdentity(
        release: '$gitlabRef@${gitlabSha.substring(0, 7)}',
        commitSha: gitlabSha,
        releaseRefKind: tag != null ? 'tag' : 'branch',
      );
    }
    return const ReleaseIdentity();
  }

  static String? _nonEmpty(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }
}
