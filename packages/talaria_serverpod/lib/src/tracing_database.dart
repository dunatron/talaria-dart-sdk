import 'package:serverpod/serverpod.dart';
import 'package:talaria/talaria.dart';

import 'session_spans.dart';

/// Delegating [Database] that emits a CLIENT span per ORM / SQL call.
class TracingDatabase implements Database {
  TracingDatabase(
    this.inner, {
    required this.client,
    required this.session,
  });

  final Database inner;
  final TalariaClient client;
  final Session session;

  String get _system {
    return inner.dialect == DatabaseDialect.sqlite ? 'sqlite' : 'postgresql';
  }

  Span? get _parent {
    final sessionId = SessionSpans.sessionIdOf(session);
    return SpanScope.forSession(sessionId) ??
        (SpanScope.zoneStack() != null ? client.tracer.currentSpan : null);
  }

  Future<T> _trace<T>({
    required String operation,
    String? table,
    String? queryText,
    required Future<T> Function() run,
  }) {
    if (!client.tracer.isEnabled) {
      return run();
    }
    final sessionId = SessionSpans.sessionIdOf(session);
    return SpanScope.runAsync(
      () {
        return DbSpan.traceOperation(
          client,
          system: _system,
          operation: operation,
          table: table,
          queryText: queryText,
          parent: _parent,
          run: run,
        );
      },
      sessionId: sessionId,
    );
  }

  static String tableName<T>() {
    final name = T.toString();
    return name.endsWith('?') ? name.substring(0, name.length - 1) : name;
  }

  @override
  DatabaseAnalyzer get analyzer => inner.analyzer;

  @override
  DatabaseDialect get dialect => inner.dialect;

  @override
  DatabaseSerializationManager get serializationManager =>
      inner.serializationManager;

  @override
  Future<List<T>> find<T extends TableRow>({
    Expression? where,
    int? limit,
    int? offset,
    Column? orderBy,
    List<Column>? orderByList,
    Transaction? transaction,
    Include? include,
    LockMode? lockMode,
    LockBehavior? lockBehavior,
  }) {
    return _trace(
      operation: 'SELECT',
      table: tableName<T>(),
      run: () => inner.find<T>(
        where: where,
        limit: limit,
        offset: offset,
        orderBy: orderBy,
        orderByList: orderByList,
        transaction: transaction,
        include: include,
        lockMode: lockMode,
        lockBehavior: lockBehavior,
      ),
    );
  }

  @override
  Future<T?> findFirstRow<T extends TableRow>({
    Expression? where,
    int? offset,
    Column? orderBy,
    List<Column>? orderByList,
    Transaction? transaction,
    Include? include,
    LockMode? lockMode,
    LockBehavior? lockBehavior,
  }) {
    return _trace(
      operation: 'SELECT',
      table: tableName<T>(),
      run: () => inner.findFirstRow<T>(
        where: where,
        offset: offset,
        orderBy: orderBy,
        orderByList: orderByList,
        transaction: transaction,
        include: include,
        lockMode: lockMode,
        lockBehavior: lockBehavior,
      ),
    );
  }

  @override
  Future<T?> findById<T extends TableRow>(
    Object id, {
    Transaction? transaction,
    Include? include,
    LockMode? lockMode,
    LockBehavior? lockBehavior,
  }) {
    return _trace(
      operation: 'SELECT',
      table: tableName<T>(),
      run: () => inner.findById<T>(
        id,
        transaction: transaction,
        include: include,
        lockMode: lockMode,
        lockBehavior: lockBehavior,
      ),
    );
  }

  @override
  Future<void> lockRows<T extends TableRow>({
    required Expression where,
    required LockMode lockMode,
    required Transaction transaction,
    LockBehavior lockBehavior = LockBehavior.wait,
  }) {
    return _trace(
      operation: 'SELECT',
      table: tableName<T>(),
      run: () => inner.lockRows<T>(
        where: where,
        lockMode: lockMode,
        transaction: transaction,
        lockBehavior: lockBehavior,
      ),
    );
  }

  @override
  Future<List<T>> update<T extends TableRow>(
    List<T> rows, {
    List<Column>? columns,
    Transaction? transaction,
    bool noReturn = false,
  }) {
    return _trace(
      operation: 'UPDATE',
      table: tableName<T>(),
      run: () => inner.update<T>(
        rows,
        columns: columns,
        transaction: transaction,
        noReturn: noReturn,
      ),
    );
  }

  @override
  Future<T> updateRow<T extends TableRow>(
    T row, {
    List<Column>? columns,
    Transaction? transaction,
  }) {
    return _trace(
      operation: 'UPDATE',
      table: tableName<T>(),
      run: () => inner.updateRow<T>(
        row,
        columns: columns,
        transaction: transaction,
      ),
    );
  }

  @override
  Future<T?> updateById<T extends TableRow>(
    Object id, {
    required List<ColumnValue> columnValues,
    Transaction? transaction,
  }) {
    return _trace(
      operation: 'UPDATE',
      table: tableName<T>(),
      run: () => inner.updateById<T>(
        id,
        columnValues: columnValues,
        transaction: transaction,
      ),
    );
  }

  @override
  Future<List<T>> updateWhere<T extends TableRow>({
    required List<ColumnValue> columnValues,
    required Expression where,
    int? limit,
    int? offset,
    Column? orderBy,
    List<Column>? orderByList,
    Transaction? transaction,
    bool noReturn = false,
  }) {
    return _trace(
      operation: 'UPDATE',
      table: tableName<T>(),
      run: () => inner.updateWhere<T>(
        columnValues: columnValues,
        where: where,
        limit: limit,
        offset: offset,
        orderBy: orderBy,
        orderByList: orderByList,
        transaction: transaction,
        noReturn: noReturn,
      ),
    );
  }

  @override
  Future<List<T>> insert<T extends TableRow>(
    List<T> rows, {
    Transaction? transaction,
    bool ignoreConflicts = false,
    bool noReturn = false,
  }) {
    return _trace(
      operation: 'INSERT',
      table: tableName<T>(),
      run: () => inner.insert<T>(
        rows,
        transaction: transaction,
        ignoreConflicts: ignoreConflicts,
        noReturn: noReturn,
      ),
    );
  }

  @override
  Future<T> insertRow<T extends TableRow>(
    T row, {
    Transaction? transaction,
  }) {
    return _trace(
      operation: 'INSERT',
      table: tableName<T>(),
      run: () => inner.insertRow<T>(row, transaction: transaction),
    );
  }

  @override
  Future<List<T>> upsert<T extends TableRow>(
    List<T> rows, {
    required List<Column> conflictColumns,
    List<Column>? updateColumns,
    Expression? updateWhere,
    Transaction? transaction,
    bool noReturn = false,
  }) {
    return _trace(
      operation: 'UPSERT',
      table: tableName<T>(),
      run: () => inner.upsert<T>(
        rows,
        conflictColumns: conflictColumns,
        updateColumns: updateColumns,
        updateWhere: updateWhere,
        transaction: transaction,
        noReturn: noReturn,
      ),
    );
  }

  @override
  Future<T?> upsertRow<T extends TableRow>(
    T row, {
    required List<Column> conflictColumns,
    List<Column>? updateColumns,
    Expression? updateWhere,
    Transaction? transaction,
  }) {
    return _trace(
      operation: 'UPSERT',
      table: tableName<T>(),
      run: () => inner.upsertRow<T>(
        row,
        conflictColumns: conflictColumns,
        updateColumns: updateColumns,
        updateWhere: updateWhere,
        transaction: transaction,
      ),
    );
  }

  @override
  Future<List<T>> delete<T extends TableRow>(
    List<T> rows, {
    Column? orderBy,
    List<Column>? orderByList,
    Transaction? transaction,
    bool noReturn = false,
  }) {
    return _trace(
      operation: 'DELETE',
      table: tableName<T>(),
      run: () => inner.delete<T>(
        rows,
        orderBy: orderBy,
        orderByList: orderByList,
        transaction: transaction,
        noReturn: noReturn,
      ),
    );
  }

  @override
  Future<T> deleteRow<T extends TableRow>(
    T row, {
    Transaction? transaction,
  }) {
    return _trace(
      operation: 'DELETE',
      table: tableName<T>(),
      run: () => inner.deleteRow<T>(row, transaction: transaction),
    );
  }

  @override
  Future<List<T>> deleteWhere<T extends TableRow>({
    required Expression where,
    Column? orderBy,
    List<Column>? orderByList,
    Transaction? transaction,
    bool noReturn = false,
  }) {
    return _trace(
      operation: 'DELETE',
      table: tableName<T>(),
      run: () => inner.deleteWhere<T>(
        where: where,
        orderBy: orderBy,
        orderByList: orderByList,
        transaction: transaction,
        noReturn: noReturn,
      ),
    );
  }

  @override
  Future<int> count<T extends TableRow>({
    Expression? where,
    int? limit,
    bool useCache = true,
    Transaction? transaction,
  }) {
    return _trace(
      operation: 'SELECT',
      table: tableName<T>(),
      run: () => inner.count<T>(
        where: where,
        limit: limit,
        useCache: useCache,
        transaction: transaction,
      ),
    );
  }

  @override
  Future<DatabaseResult> unsafeQuery(
    String query, {
    int? timeoutInSeconds,
    Transaction? transaction,
    QueryParameters? parameters,
  }) {
    return _trace(
      operation: SqlSanitizer.operation(query),
      table: SqlSanitizer.table(query),
      queryText: query,
      run: () => inner.unsafeQuery(
        query,
        timeoutInSeconds: timeoutInSeconds,
        transaction: transaction,
        parameters: parameters,
      ),
    );
  }

  @override
  Future<int> unsafeExecute(
    String query, {
    int? timeoutInSeconds,
    Transaction? transaction,
    QueryParameters? parameters,
  }) {
    return _trace(
      operation: SqlSanitizer.operation(query),
      table: SqlSanitizer.table(query),
      queryText: query,
      run: () => inner.unsafeExecute(
        query,
        timeoutInSeconds: timeoutInSeconds,
        transaction: transaction,
        parameters: parameters,
      ),
    );
  }

  @override
  Future<DatabaseResult> unsafeSimpleQuery(
    String query, {
    int? timeoutInSeconds,
    Transaction? transaction,
  }) {
    return _trace(
      operation: SqlSanitizer.operation(query),
      table: SqlSanitizer.table(query),
      queryText: query,
      run: () => inner.unsafeSimpleQuery(
        query,
        timeoutInSeconds: timeoutInSeconds,
        transaction: transaction,
      ),
    );
  }

  @override
  Future<int> unsafeSimpleExecute(
    String query, {
    int? timeoutInSeconds,
    Transaction? transaction,
  }) {
    return _trace(
      operation: SqlSanitizer.operation(query),
      table: SqlSanitizer.table(query),
      queryText: query,
      run: () => inner.unsafeSimpleExecute(
        query,
        timeoutInSeconds: timeoutInSeconds,
        transaction: transaction,
      ),
    );
  }

  @override
  Future<R> transaction<R>(
    TransactionFunction<R> transactionFunction, {
    TransactionSettings? settings,
  }) {
    return inner.transaction(transactionFunction, settings: settings);
  }

  @override
  Future<bool> testConnection() => inner.testConnection();
}
