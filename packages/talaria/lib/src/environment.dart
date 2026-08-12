/// Wire environments accepted by Talaria ingest.
enum Environment {
  production('production'),
  staging('staging'),
  development('development');

  const Environment(this.wireValue);

  final String wireValue;

  /// Parse wire or alias values (`prod`/`live`, `test`/`uat`, `dev`/`local`).
  static Environment fromMixed(Object environment) {
    if (environment is Environment) {
      return environment;
    }
    final normalized = environment.toString().trim().toLowerCase();
    return switch (normalized) {
      'prod' || 'production' || 'live' => Environment.production,
      'stage' || 'staging' || 'uat' || 'test' => Environment.staging,
      'dev' || 'development' || 'local' => Environment.development,
      _ => Environment.production,
    };
  }
}
