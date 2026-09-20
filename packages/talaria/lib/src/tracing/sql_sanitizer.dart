/// Best-effort SQL literal stripping so query text is low-risk to send.
///
/// ANSI / Serverpod identifiers use double quotes. Only single-quoted
/// literals and numeric tokens are replaced. Matches the PHP SDK.
class SqlSanitizer {
  SqlSanitizer._();

  static const int maxLength = 1024;

  static String sanitize(String sql) {
    var stripped = sql.replaceAll(RegExp(r"'(?:\\'|[^'])*'"), '?');
    stripped = stripped.replaceAllMapped(RegExp(r'"([^"]*)"'), (match) {
      final inner = match.group(1) ?? '';
      if (RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(inner)) {
        return match.group(0)!;
      }
      return '?';
    });
    stripped = stripped.replaceAll(RegExp(r'\b\d+\b'), '?');
    stripped = stripped.replaceAll(RegExp(r'\s+'), ' ').trim();

    if (stripped.length > maxLength) {
      return '${stripped.substring(0, maxLength - 3)}...';
    }
    return stripped;
  }

  static String operation(String sql) {
    final match = RegExp(r'^\s*([A-Za-z]+)').firstMatch(sql);
    if (match != null) {
      return match.group(1)!.toUpperCase();
    }
    return 'QUERY';
  }

  /// Primary table/collection from FROM / INTO / UPDATE / TABLE, if present.
  static String? table(String sql) {
    final match = RegExp(
      r'\b(?:FROM|INTO|UPDATE|TABLE)\s+(?:`|"|\[)?([A-Za-z_][A-Za-z0-9_.]*)',
      caseSensitive: false,
    ).firstMatch(sql);
    if (match == null) {
      return null;
    }
    final name = match.group(1)!;
    if (name.toUpperCase() == 'SELECT') {
      return null;
    }
    return name;
  }

  /// OTel-style span name: `SELECT SiteTree`, or `SHOW` when there is no table.
  static String spanName(String sql) {
    final op = operation(sql);
    final collection = table(sql);
    return collection != null ? '$op $collection' : op;
  }

  static String spanNameFor({
    required String operation,
    String? table,
  }) {
    final op = operation.trim().isEmpty ? 'QUERY' : operation.toUpperCase();
    if (table == null || table.isEmpty) {
      return op;
    }
    return '$op $table';
  }

  static Map<String, String> attributes(String sql, String system) {
    final op = operation(sql);
    final collection = table(sql);
    return {
      'db.system.name': system,
      'db.operation.name': op,
      'db.query.text': sanitize(sql),
      if (collection != null) 'db.collection.name': collection,
    };
  }

  static Map<String, String> attributesForOperation({
    required String system,
    required String operation,
    String? table,
    String? queryText,
  }) {
    final op = operation.trim().isEmpty ? 'QUERY' : operation.toUpperCase();
    final standIn = queryText != null && queryText.isNotEmpty
        ? sanitize(queryText)
        : spanNameFor(operation: op, table: table);
    return {
      'db.system.name': system,
      'db.operation.name': op,
      'db.query.text': standIn,
      if (table != null && table.isNotEmpty) 'db.collection.name': table,
    };
  }
}
