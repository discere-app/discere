import 'package:discere/shared/persistence/schema/schema_asset.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('splitSqlStatements', () {
    test('splits on statement boundaries and drops the empty tail', () {
      expect(splitSqlStatements('CREATE TABLE a (x INTEGER);'), [
        'CREATE TABLE a (x INTEGER)',
      ]);
    });

    test('keeps blank lines between statements out of the result', () {
      final statements = splitSqlStatements('''
CREATE TABLE a (x INTEGER);

CREATE INDEX idx_a ON a(x);
''');
      expect(statements, hasLength(2));
      expect(statements.first, 'CREATE TABLE a (x INTEGER)');
      expect(statements.last, 'CREATE INDEX idx_a ON a(x)');
    });

    test('accepts a final statement without a trailing semicolon', () {
      expect(splitSqlStatements('CREATE TABLE a (x INTEGER)'), hasLength(1));
    });

    /// A default is the one place an asset can legitimately carry a semicolon,
    /// and splitting inside it would produce two statements that are each
    /// invalid SQL — the schema would fail to build for a reason nothing in
    /// the asset hints at.
    test('does not split on a semicolon inside a string literal', () {
      final statements = splitSqlStatements(
        "CREATE TABLE a (x TEXT DEFAULT 'left;right');",
      );
      expect(statements, hasLength(1));
      expect(statements.single, contains("'left;right'"));
    });

    /// The assets document their tables with `--` lines, including above the
    /// CREATE TABLE itself.
    test('drops line comments', () {
      final statements = splitSqlStatements('''
-- Identity row for a species.
CREATE TABLE a (x INTEGER);
-- An index over it.
CREATE INDEX idx_a ON a(x);
''');
      expect(statements, hasLength(2));
      expect(statements.first, 'CREATE TABLE a (x INTEGER)');
      expect(statements.last, 'CREATE INDEX idx_a ON a(x)');
    });

    /// A comment between two column definitions must not run them together.
    test('keeps columns separate when a comment sits between them', () {
      final statements = splitSqlStatements('''
CREATE TABLE a (
  x INTEGER, -- the first
  y INTEGER
);
''');
      expect(statements, hasLength(1));
      expect(statements.single, contains('x INTEGER,'));
      expect(statements.single, contains('y INTEGER'));
    });

    test('does not treat a semicolon inside a comment as a boundary', () {
      expect(
        splitSqlStatements('-- a; b\nCREATE TABLE a (x INTEGER);'),
        hasLength(1),
      );
    });

    test('treats a doubled quote as an escape, not the end of the literal', () {
      final statements = splitSqlStatements(
        "CREATE TABLE a (x TEXT DEFAULT 'it''s; fine');",
      );
      expect(statements, hasLength(1));
      expect(statements.single, contains("'it''s; fine'"));
    });
  });

  group('SchemaAsset.parse', () {
    test('separates the table from its indexes', () {
      final asset = SchemaAsset.parse('''
CREATE TABLE IF NOT EXISTS widgets (
  id   TEXT PRIMARY KEY,
  name TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_widgets_name ON widgets(name);
''');

      expect(asset.tableName, 'widgets');
      expect(asset.isVirtual, isFalse);
      expect(asset.createTable, startsWith('CREATE TABLE IF NOT EXISTS'));
      expect(asset.indexes, hasLength(1));
      expect(asset.indexes.single, contains('idx_widgets_name'));
    });

    test('recognises a virtual FTS table', () {
      final asset = SchemaAsset.parse(
        'CREATE VIRTUAL TABLE IF NOT EXISTS docs_fts USING fts4(body);',
      );
      expect(asset.tableName, 'docs_fts');
      expect(asset.isVirtual, isTrue);
    });

    test('rejects an asset with no table', () {
      expect(
        () => SchemaAsset.parse('CREATE INDEX idx_a ON a(x);'),
        throwsA(isA<FormatException>()),
      );
    });

    /// Reconciliation addresses one table per asset, so a second one here
    /// would never be widened — it would only ever be created.
    test('rejects an asset declaring two tables', () {
      expect(
        () => SchemaAsset.parse(
          'CREATE TABLE a (x INT); CREATE TABLE b (y INT);',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    /// Anything else in the file would be dropped on the floor by the
    /// reconciler, which only replays tables and indexes.
    test('rejects a statement that is neither a table nor an index', () {
      expect(
        () => SchemaAsset.parse(
          'CREATE TABLE a (x INT); INSERT INTO a VALUES (1);',
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('createTableAs', () {
    test('renames the created table and nothing else', () {
      final asset = SchemaAsset.parse('''
CREATE TABLE IF NOT EXISTS deck_config (
  deck_id TEXT PRIMARY KEY REFERENCES decks(id) ON DELETE CASCADE,
  review_mode TEXT NOT NULL DEFAULT 'flip'
);
''');

      final renamed = asset.createTableAs('deck_config__probe');

      expect(renamed, contains('EXISTS deck_config__probe ('));
      // The foreign key still points at the real table, and the column keeps
      // its name even though it shares the prefix.
      expect(renamed, contains('REFERENCES decks(id)'));
      expect(renamed, contains('deck_id TEXT PRIMARY KEY'));
      expect(renamed, contains("DEFAULT 'flip'"));
    });
  });
}
