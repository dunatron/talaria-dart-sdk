import 'dart:convert';

import 'flag_evaluation.dart';

/// Wire-shaped flag definition for local evaluation (`flags/downloadDefinitions`).
class FlagDefinition {
  const FlagDefinition({
    required this.key,
    required this.kind,
    required this.variations,
    required this.rules,
    required this.defaultVariationKey,
    required this.offVariationKey,
    required this.enabled,
    required this.version,
  });

  final String key;
  final String kind;
  final List<FlagVariationDefinition> variations;
  final List<FlagRuleDefinition> rules;
  final String defaultVariationKey;
  final String offVariationKey;
  final bool enabled;
  final int version;

  factory FlagDefinition.fromWire(Map<String, Object?> raw) {
    final variationsRaw = raw['variations'];
    final rulesRaw = raw['rules'];
    return FlagDefinition(
      key: (raw['key'] as String?)?.trim() ?? '',
      kind: (raw['kind'] as String?)?.trim() ?? 'boolean',
      variations: variationsRaw is List
          ? [
              for (final item in variationsRaw)
                if (item is Map)
                  FlagVariationDefinition.fromWire(
                    item.map((k, v) => MapEntry(k.toString(), v)),
                  ),
            ]
          : const [],
      rules: rulesRaw is List
          ? [
              for (final item in rulesRaw)
                if (item is Map)
                  FlagRuleDefinition.fromWire(
                    item.map((k, v) => MapEntry(k.toString(), v)),
                  ),
            ]
          : const [],
      defaultVariationKey:
          (raw['defaultVariationKey'] as String?)?.trim() ?? '',
      offVariationKey: (raw['offVariationKey'] as String?)?.trim() ?? '',
      enabled: raw['enabled'] == true,
      version: (raw['version'] as num?)?.toInt() ?? 0,
    );
  }

  FlagVariationDefinition? variationByKey(String variationKey) {
    for (final v in variations) {
      if (v.key == variationKey) return v;
    }
    return null;
  }
}

class FlagVariationDefinition {
  const FlagVariationDefinition({
    required this.key,
    required this.value,
    this.valueJson,
    this.name,
  });

  final String key;
  final Object? value;
  final String? valueJson;
  final String? name;

  factory FlagVariationDefinition.fromWire(Map<String, Object?> raw) {
    final valueJson = raw['valueJson'] as String?;
    return FlagVariationDefinition(
      key: (raw['key'] as String?)?.trim() ?? '',
      value: FlagEvaluationResult.decodeValueJson(valueJson),
      valueJson: valueJson,
      name: raw['name'] as String?,
    );
  }
}

class FlagRuleDefinition {
  const FlagRuleDefinition({
    required this.kind,
    required this.variationKey,
    this.percent,
    this.includeIds = const [],
    this.excludeIds = const [],
    this.attributeKey,
    this.attributeOp,
    this.attributeValues = const [],
  });

  final String kind;
  final String variationKey;
  final int? percent;
  final List<String> includeIds;
  final List<String> excludeIds;
  final String? attributeKey;
  final String? attributeOp;
  final List<String> attributeValues;

  factory FlagRuleDefinition.fromWire(Map<String, Object?> raw) {
    List<String> stringList(Object? value) {
      if (value is! List) return const [];
      return [
        for (final item in value)
          if (item != null) item.toString(),
      ];
    }

    return FlagRuleDefinition(
      kind: (raw['kind'] as String?)?.trim() ?? 'always',
      variationKey: (raw['variationKey'] as String?)?.trim() ?? '',
      percent: (raw['percent'] as num?)?.toInt(),
      includeIds: stringList(raw['includeIds']),
      excludeIds: stringList(raw['excludeIds']),
      attributeKey: raw['attributeKey'] as String?,
      attributeOp: raw['attributeOp'] as String?,
      attributeValues: stringList(raw['attributeValues']),
    );
  }
}

/// Context for [LocalFlagEvaluator] (mirrors server FlagEvaluationContext).
class LocalFlagContext {
  const LocalFlagContext({
    this.anonymousId,
    this.userId,
    this.organizationId,
    this.attributes = const {},
  });

  final String? anonymousId;
  final String? userId;
  final String? organizationId;
  final Map<String, String> attributes;

  String? get userBucketKey {
    final uid = userId?.trim();
    if (uid != null && uid.isNotEmpty) return uid;
    final anon = anonymousId?.trim();
    if (anon != null && anon.isNotEmpty) return anon;
    return null;
  }
}

/// Parse a `FeatureFlagListResponse`-shaped downloadDefinitions payload.
List<FlagDefinition> parseFlagDefinitions(Map<String, Object?> raw) {
  final list = raw['flags'] ?? raw['definitions'];
  if (list is! List) return const [];
  final out = <FlagDefinition>[];
  for (final item in list) {
    if (item is! Map) continue;
    final def = FlagDefinition.fromWire(
      item.map((k, v) => MapEntry(k.toString(), v)),
    );
    if (def.key.isEmpty) continue;
    out.add(def);
  }
  return out;
}

/// Encode a definition list for disk cache.
String encodeFlagDefinitionsCache(List<FlagDefinition> defs) {
  return jsonEncode({
    'flags': [
      for (final d in defs)
        {
          'key': d.key,
          'kind': d.kind,
          'variations': [
            for (final v in d.variations)
              {
                'key': v.key,
                'valueJson':
                    v.valueJson ?? FlagEvaluationResult.encodeValueJson(v.value),
                if (v.name != null) 'name': v.name,
              },
          ],
          'rules': [
            for (final r in d.rules)
              {
                'kind': r.kind,
                'variationKey': r.variationKey,
                if (r.percent != null) 'percent': r.percent,
                if (r.includeIds.isNotEmpty) 'includeIds': r.includeIds,
                if (r.excludeIds.isNotEmpty) 'excludeIds': r.excludeIds,
                if (r.attributeKey != null) 'attributeKey': r.attributeKey,
                if (r.attributeOp != null) 'attributeOp': r.attributeOp,
                if (r.attributeValues.isNotEmpty)
                  'attributeValues': r.attributeValues,
              },
          ],
          'defaultVariationKey': d.defaultVariationKey,
          'offVariationKey': d.offVariationKey,
          'enabled': d.enabled,
          'version': d.version,
        },
    ],
  });
}
