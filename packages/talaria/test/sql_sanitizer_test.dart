import 'package:talaria/talaria.dart';
import 'package:test/test.dart';

void main() {
  test('replaces single-quoted literals and numbers', () {
    const sql = "SELECT * FROM SiteTree WHERE ID = 12 AND Title = 'Home'";
    expect(
      SqlSanitizer.sanitize(sql),
      'SELECT * FROM SiteTree WHERE ID = ? AND Title = ?',
    );
  });

  test('keeps identifier double quotes and redacts other doubles', () {
    expect(
      SqlSanitizer.sanitize('SELECT "SiteTree"."Title" FROM "SiteTree"'),
      'SELECT "SiteTree"."Title" FROM "SiteTree"',
    );
    expect(
      SqlSanitizer.sanitize('SELECT * FROM t WHERE name = "not-an-id"'),
      'SELECT * FROM t WHERE name = ?',
    );
  });

  test('truncates long SQL', () {
    final sql = 'SELECT ${'x' * 2000}';
    final sanitized = SqlSanitizer.sanitize(sql);
    expect(sanitized.length, SqlSanitizer.maxLength);
    expect(sanitized.endsWith('...'), isTrue);
  });

  test('operation, table, and span name', () {
    const sql = 'INSERT INTO ApiKey (id) VALUES (1)';
    expect(SqlSanitizer.operation(sql), 'INSERT');
    expect(SqlSanitizer.table(sql), 'ApiKey');
    expect(SqlSanitizer.spanName(sql), 'INSERT ApiKey');
  });

  test('attributes include sanitized text', () {
    final attrs = SqlSanitizer.attributes(
      "SELECT * FROM users WHERE id = 9",
      'postgresql',
    );
    expect(attrs['db.system.name'], 'postgresql');
    expect(attrs['db.operation.name'], 'SELECT');
    expect(attrs['db.collection.name'], 'users');
    expect(attrs['db.query.text'], 'SELECT * FROM users WHERE id = ?');
  });

  test('attributesForOperation without raw SQL', () {
    final attrs = SqlSanitizer.attributesForOperation(
      system: 'postgresql',
      operation: 'select',
      table: 'ApiKey',
    );
    expect(attrs['db.operation.name'], 'SELECT');
    expect(attrs['db.collection.name'], 'ApiKey');
    expect(attrs['db.query.text'], 'SELECT ApiKey');
  });
}
