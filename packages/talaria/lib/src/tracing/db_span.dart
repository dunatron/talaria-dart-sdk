import '../client.dart';
import 'breadcrumbs.dart';
import 'span.dart';
import 'sql_sanitizer.dart';

/// Shared CLIENT span + query breadcrumb for SQL wrappers.
class DbSpan {
  DbSpan._();

  static Future<T> trace<T>(
    TalariaClient client, {
    required String system,
    required String sql,
    required Future<T> Function() run,
    Span? parent,
  }) {
    return traceOperation(
      client,
      system: system,
      operation: SqlSanitizer.operation(sql),
      table: SqlSanitizer.table(sql),
      queryText: sql,
      run: run,
      parent: parent,
    );
  }

  static Future<T> traceOperation<T>(
    TalariaClient client, {
    required String system,
    required String operation,
    String? table,
    String? queryText,
    required Future<T> Function() run,
    Span? parent,
  }) async {
    final name = queryText != null && queryText.isNotEmpty
        ? SqlSanitizer.spanName(queryText)
        : SqlSanitizer.spanNameFor(operation: operation, table: table);
    final attributes = queryText != null && queryText.isNotEmpty
        ? SqlSanitizer.attributes(queryText, system)
        : SqlSanitizer.attributesForOperation(
            system: system,
            operation: operation,
            table: table,
            queryText: queryText,
          );

    final span = client.startSpan(
      name,
      kind: SpanKind.client,
      attributes: attributes,
      parent: parent,
    );

    try {
      final result = await run();
      span.setStatus(SpanStatus.ok);
      client.addBreadcrumb(Breadcrumb(
        type: 'query',
        category: 'db',
        message: operation.toUpperCase(),
        level: 'info',
        data: {'db.system.name': system},
      ));
      return result;
    } catch (e) {
      span.setStatus(SpanStatus.error, message: e.toString());
      rethrow;
    } finally {
      span.finish();
    }
  }
}
