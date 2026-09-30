import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'flag_definition.dart';
import 'flag_evaluation.dart';

/// Deterministic in-process flag evaluation — same algorithm as the server
/// `FlagEvaluator`.
///
/// Bucketing: `sha256("$flagKey\n$bucketKey")` first 4 bytes big-endian `% 100`
/// (0–99 inclusive). Never uses sessionId.
class LocalFlagEvaluator {
  const LocalFlagEvaluator();

  FlagEvaluationResult evaluate(
    FlagDefinition flag,
    LocalFlagContext context,
  ) {
    if (!flag.enabled) {
      return _serve(flag, flag.offVariationKey, reason: 'off');
    }

    for (var i = 0; i < flag.rules.length; i++) {
      final rule = flag.rules[i];
      if (_matches(flag.key, rule, context)) {
        return _serve(flag, rule.variationKey, reason: 'rule:$i');
      }
    }

    return _serve(flag, flag.defaultVariationKey, reason: 'default');
  }

  List<FlagEvaluationResult> evaluateAll(
    List<FlagDefinition> flags,
    LocalFlagContext context, {
    Set<String>? keys,
  }) {
    final out = <FlagEvaluationResult>[];
    for (final flag in flags) {
      if (keys != null && keys.isNotEmpty && !keys.contains(flag.key)) {
        continue;
      }
      out.add(evaluate(flag, context));
    }
    return out;
  }

  FlagEvaluationResult _serve(
    FlagDefinition flag,
    String variationKey, {
    required String reason,
  }) {
    final variation = flag.variationByKey(variationKey) ??
        flag.variationByKey(flag.offVariationKey) ??
        (flag.variations.isNotEmpty ? flag.variations.first : null);
    return FlagEvaluationResult(
      key: flag.key,
      variationKey: variation?.key ?? variationKey,
      value: variation?.value,
      version: flag.version,
      reason: reason,
      valueJson: variation?.valueJson ??
          FlagEvaluationResult.encodeValueJson(variation?.value),
    );
  }

  bool _matches(
    String flagKey,
    FlagRuleDefinition rule,
    LocalFlagContext context,
  ) {
    switch (rule.kind) {
      case 'always':
        return true;
      case 'percentUsers':
        final bucketKey = context.userBucketKey;
        if (bucketKey == null) return false;
        final pct = rule.percent ?? 0;
        if (pct <= 0) return false;
        if (pct >= 100) return true;
        return bucket(flagKey, bucketKey) < pct;
      case 'percentOrgs':
        final orgId = context.organizationId?.trim();
        if (orgId == null || orgId.isEmpty) return false;
        final pct = rule.percent ?? 0;
        if (pct <= 0) return false;
        if (pct >= 100) return true;
        return bucket(flagKey, orgId) < pct;
      case 'userList':
        final key = context.userBucketKey;
        if (key == null) return false;
        if (rule.excludeIds.contains(key)) return false;
        if (rule.includeIds.isEmpty) return false;
        return rule.includeIds.contains(key);
      case 'orgList':
        final orgId = context.organizationId?.trim();
        if (orgId == null || orgId.isEmpty) return false;
        if (rule.excludeIds.contains(orgId)) return false;
        if (rule.includeIds.isEmpty) return false;
        return rule.includeIds.contains(orgId);
      case 'attributeMatch':
        return _matchAttribute(rule, context);
      default:
        return false;
    }
  }

  bool _matchAttribute(FlagRuleDefinition rule, LocalFlagContext context) {
    final attrKey = rule.attributeKey?.trim();
    if (attrKey == null || attrKey.isEmpty) return false;
    final actual = context.attributes[attrKey];
    if (actual == null) return false;
    final op = rule.attributeOp ?? 'equals';
    switch (op) {
      case 'equals':
        return rule.attributeValues.isNotEmpty &&
            rule.attributeValues.first == actual;
      case 'inList':
        return rule.attributeValues.contains(actual);
      case 'contains':
        return rule.attributeValues.any((v) => actual.contains(v));
      default:
        return false;
    }
  }

  /// Returns 0–99 inclusive. Stable for `(flagKey, bucketKey)`.
  ///
  /// Algorithm: `sha256("$flagKey\n$bucketKey")` → first 4 bytes big-endian → `% 100`.
  static int bucket(String flagKey, String bucketKey) {
    final digest = sha256.convert(utf8.encode('$flagKey\n$bucketKey'));
    final bytes = digest.bytes;
    final n = (bytes[0] << 24) |
        (bytes[1] << 16) |
        (bytes[2] << 8) |
        bytes[3];
    return n.abs() % 100;
  }
}
