import 'package:talaria/talaria.dart';
import 'package:test/test.dart';

void main() {
  // Known fixture: sha256("new-checkout\nstable-user") first 4 bytes BE % 100 = 59
  // (matches server FlagEvaluator / PHP LocalFlagEvaluator).
  const flagKey = 'new-checkout';
  const bucketKey = 'stable-user';
  const expectedBucket = 59;

  test('bucket matches server hash fixture', () {
    expect(LocalFlagEvaluator.bucket(flagKey, bucketKey), expectedBucket);
  });

  test('percentUsers includes when bucket < percent', () {
    const evaluator = LocalFlagEvaluator();
    final flag = FlagDefinition(
      key: flagKey,
      kind: 'boolean',
      variations: const [
        FlagVariationDefinition(key: 'on', value: true, valueJson: 'true'),
        FlagVariationDefinition(key: 'off', value: false, valueJson: 'false'),
      ],
      rules: const [
        FlagRuleDefinition(
          kind: 'percentUsers',
          variationKey: 'on',
          percent: 60,
        ),
      ],
      defaultVariationKey: 'off',
      offVariationKey: 'off',
      enabled: true,
      version: 1,
    );
    final inRollout = evaluator.evaluate(
      flag,
      const LocalFlagContext(userId: bucketKey),
    );
    expect(inRollout.variationKey, 'on');
    expect(inRollout.reason, 'rule:0');

    final outOfRollout = evaluator.evaluate(
      FlagDefinition(
        key: flagKey,
        kind: 'boolean',
        variations: flag.variations,
        rules: const [
          FlagRuleDefinition(
            kind: 'percentUsers',
            variationKey: 'on',
            percent: 50,
          ),
        ],
        defaultVariationKey: 'off',
        offVariationKey: 'off',
        enabled: true,
        version: 1,
      ),
      const LocalFlagContext(userId: bucketKey),
    );
    expect(outOfRollout.variationKey, 'off');
    expect(outOfRollout.reason, 'default');
  });

  test('anonymousId buckets the same as userId for same string', () {
    expect(
      LocalFlagEvaluator.bucket(flagKey, 'anon-1'),
      LocalFlagEvaluator.bucket(flagKey, 'anon-1'),
    );
    const evaluator = LocalFlagEvaluator();
    final flag = FlagDefinition(
      key: flagKey,
      kind: 'boolean',
      variations: const [
        FlagVariationDefinition(key: 'on', value: true, valueJson: 'true'),
        FlagVariationDefinition(key: 'off', value: false, valueJson: 'false'),
      ],
      rules: const [
        FlagRuleDefinition(
          kind: 'percentUsers',
          variationKey: 'on',
          percent: 100,
        ),
      ],
      defaultVariationKey: 'off',
      offVariationKey: 'off',
      enabled: true,
      version: 1,
    );
    final a = evaluator.evaluate(
      flag,
      const LocalFlagContext(anonymousId: 'anon-1'),
    );
    final b = evaluator.evaluate(
      flag,
      const LocalFlagContext(userId: 'anon-1'),
    );
    expect(a.variationKey, b.variationKey);
    expect(a.reason, b.reason);
  });
}
