/// One `create_*.sql` schema asset, split into the statements it declares.
///
/// The assets are the single source of truth for what the current user schema
/// looks like: a fresh install is exactly what they produce. [SchemaReconciler]
/// uses that to bring an existing database to the same shape, which means it
/// has to know the statements apart — a column has to be added before an index
/// over it can be built, and only the table statement says which columns a
/// table should have.
class SchemaAsset {
  const SchemaAsset({
    required this.tableName,
    required this.createTable,
    required this.indexes,
    required this.isVirtual,
  });

  /// Parses one asset's SQL text.
  ///
  /// Throws [FormatException] if the text declares no table — every asset this
  /// is used with creates exactly one, and a silent empty result here would
  /// leave that table out of reconciliation entirely.
  factory SchemaAsset.parse(String sql) {
    String? tableName;
    String? createTable;
    var isVirtual = false;
    final indexes = <String>[];

    for (final statement in splitSqlStatements(sql)) {
      final table = _tableHeader.firstMatch(statement);
      if (table != null) {
        if (tableName != null) {
          throw FormatException(
            'Schema asset declares more than one table ($tableName and '
            '${table.namedGroup('name')}); reconciliation addresses a table '
            'by its own asset, so each needs its own file.',
            sql,
          );
        }
        tableName = table.namedGroup('name');
        createTable = statement;
        isVirtual = table.namedGroup('virtual') != null;
        continue;
      }
      if (_indexHeader.hasMatch(statement)) {
        indexes.add(statement);
        continue;
      }
      throw FormatException(
        'Schema asset contains a statement that is neither a CREATE TABLE nor '
        'a CREATE INDEX. Reconciliation would silently skip it.',
        statement,
      );
    }

    if (tableName == null || createTable == null) {
      throw FormatException('Schema asset declares no table.', sql);
    }
    return SchemaAsset(
      tableName: tableName,
      createTable: createTable,
      indexes: indexes,
      isVirtual: isVirtual,
    );
  }

  /// The table this asset creates.
  final String tableName;

  /// The `CREATE TABLE` statement, without a trailing `;`.
  final String createTable;

  /// The `CREATE INDEX` statements over [tableName], without trailing `;`.
  final List<String> indexes;

  /// Whether [tableName] is a virtual (FTS) table. Those carry no ordinary
  /// columns and cannot be `ALTER`ed, so reconciliation only ever creates
  /// them, never widens them.
  final bool isVirtual;

  /// [createTable] with the table renamed to [name].
  ///
  /// Reconciliation needs the column list a *fresh* table would have. Rather
  /// than parse the column definitions — which means reimplementing a corner
  /// of SQLite's grammar and being wrong about some corner of it — it creates
  /// the table once under a throwaway name and reads the answer back with
  /// `PRAGMA table_info`. SQLite stays the parser.
  String createTableAs(String name) {
    final header = _tableHeader.firstMatch(createTable);
    if (header == null) {
      throw StateError('createTable no longer matches the table header.');
    }
    final start = header.start + header.group(0)!.lastIndexOf(tableName);
    return createTable.replaceRange(start, start + tableName.length, name);
  }

  /// `CREATE TABLE [IF NOT EXISTS] <name>` / `CREATE VIRTUAL TABLE …`.
  static final _tableHeader = RegExp(
    r'^\s*CREATE\s+(?<virtual>VIRTUAL\s+)?TABLE\s+'
    r'(?:IF\s+NOT\s+EXISTS\s+)?(?<name>[A-Za-z_][A-Za-z0-9_]*)',
    caseSensitive: false,
  );

  static final _indexHeader = RegExp(
    r'^\s*CREATE\s+(?:UNIQUE\s+)?INDEX\s',
    caseSensitive: false,
  );
}

/// Splits [sql] into its individual statements.
///
/// `db.execute()` takes a whole asset today and the host driver runs every
/// statement in it, but reconciliation needs them apart anyway: the order
/// tables → columns → indexes is the point, and it spans assets rather than
/// following the order inside one file.
///
/// Comments are dropped: the assets document their tables with `--` lines, and
/// a comment is neither a statement nor part of the one that follows it.
///
/// Semicolons inside a string literal do not separate statements — no current
/// asset has one, and a default like `DEFAULT 'a;b'` should not be the thing
/// that breaks the schema.
List<String> splitSqlStatements(String sql) {
  final statements = <String>[];
  final buffer = StringBuffer();
  var inString = false;

  for (var i = 0; i < sql.length; i++) {
    final char = sql[i];
    if (!inString && char == '-' && i + 1 < sql.length && sql[i + 1] == '-') {
      final lineEnd = sql.indexOf('\n', i);
      if (lineEnd == -1) break;
      // Keep the newline, so a comment between two column definitions does
      // not run them together.
      i = lineEnd - 1;
      continue;
    }
    if (!inString && char == '/' && i + 1 < sql.length && sql[i + 1] == '*') {
      final blockEnd = sql.indexOf('*/', i + 2);
      if (blockEnd == -1) {
        throw FormatException(
          'Unterminated block comment in schema asset.',
          sql,
        );
      }
      i = blockEnd + 1;
      continue;
    }
    if (char == "'") {
      // `''` is an escaped quote inside a literal, not its end.
      if (inString && i + 1 < sql.length && sql[i + 1] == "'") {
        buffer.write("''");
        i++;
        continue;
      }
      inString = !inString;
      buffer.write(char);
      continue;
    }
    if (char == ';' && !inString) {
      _addStatement(statements, buffer);
      continue;
    }
    buffer.write(char);
  }
  _addStatement(statements, buffer);
  return statements;
}

void _addStatement(List<String> statements, StringBuffer buffer) {
  final statement = buffer.toString().trim();
  buffer.clear();
  if (statement.isEmpty) return;
  statements.add(statement);
}
