import 'package:discere/shared/persistence/schema/schema_asset.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:sqflite/sqflite.dart';

/// Brings a user database to the structural shape the current schema assets
/// describe: missing tables are created, missing columns added, missing indexes
/// built.
///
/// ## Why this exists
///
/// A migration describes the schema as it was at its own version (ARCH-13), so
/// no migration can be the place that guarantees the *current* shape. Something
/// has to close the gap between "every migration ran" and "the schema matches
/// what a fresh install gets", and it has to do so without being a list someone
/// remembers to extend: the assets already say what the shape is, so this reads
/// them rather than restating them.
///
/// That replaces a hand-maintained repair table. Such a table has to be
/// extended by whoever adds a column, in a second place, with nothing checking
/// that they did — and the columns it did not cover simply had no repair at
/// all. Deriving the work from the assets removes the class of mistake instead
/// of asking people to avoid it.
///
/// ## Structure only, never data
///
/// A missing table or column is unambiguous: the asset says it should be there
/// and it is not. Data is not. Reconciliation cannot tell "a migration failed
/// to backfill this" from "this is legitimately empty", so it never writes a
/// row and never rewrites one.
///
/// The cost of getting that wrong is asymmetric. A missing column throws on
/// every query that names it — loud, immediate, reported. A wrongly backfilled
/// review stat shifts a card's due date and surfaces days later as "that card
/// came back far too early", with nothing in the logs. A backstop that heals
/// data turns the first failure mode into the second.
///
/// ## When it runs
///
/// From `UserDbSchema.create` (where every table is missing, so it is simply
/// the create path) and at the end of `UserDbSchema.upgrade`.
///
/// Deliberately *not* on every open. The case that would need it is a database
/// that arrives already at the current version without ever running the
/// migration ladder — a restore from a backup, or a file copied between
/// devices. Discere has no such path today: a user database is either created
/// here or upgraded in place. Adding an explicit restore (issue #204) is what
/// creates it, and that path should call [reconcile] itself rather than every
/// app start paying for a check that cannot currently find anything.
class SchemaReconciler {
  SchemaReconciler._();

  static final _log = Logger.forType(SchemaReconciler);

  /// Suffix for the throwaway table [_addMissingColumns] reads a fresh column
  /// list from. Names a table nothing else may use.
  static const _probeSuffix = '__schema_probe';

  /// Reconciles [db] against [assets], in the one order that works: every
  /// table first, then the columns each is missing, then the indexes — an
  /// index may well cover a column added a moment earlier, and building it
  /// before that column exists is exactly the failure this whole area keeps
  /// producing.
  static Future<void> reconcile(Database db, List<SchemaAsset> assets) async {
    for (final asset in assets) {
      if (!await _tableExists(db, asset.tableName)) {
        await db.execute(asset.createTable);
        // A table just created from the asset already has every column the
        // asset names, so there is nothing to widen.
        continue;
      }
      if (asset.isVirtual) continue;
      await _addMissingColumns(db, asset);
    }

    for (final asset in assets) {
      for (final statement in asset.indexes) {
        await db.execute(statement);
      }
    }
  }

  static Future<void> _addMissingColumns(Database db, SchemaAsset asset) async {
    final probe = '${asset.tableName}$_probeSuffix';
    // A probe left behind by an interrupted earlier run would make the
    // CREATE below a silent no-op, and the column list would then be read
    // from whatever that stale table happens to hold.
    await db.execute('DROP TABLE IF EXISTS $probe');
    await db.execute(asset.createTableAs(probe));
    try {
      final intended = await _columns(db, probe);
      final present = (await _columns(
        db,
        asset.tableName,
      )).map((column) => column.name).toSet();

      for (final column in intended) {
        if (present.contains(column.name)) continue;
        if (!column.canBeAdded) {
          // Raised rather than skipped: skipping leaves the column missing,
          // and every query naming it fails later with nothing to say why.
          throw StateError(
            'Cannot reconcile ${asset.tableName}: the asset declares '
            '${column.name} as ${column.notAddableReason}, which SQLite '
            'cannot add to a table that already exists. A column added to a '
            'shipped table has to be nullable or carry a default — otherwise '
            'a fresh install gets it and no existing database ever can.',
          );
        }
        _log.info(
          'Reconciling ${asset.tableName}: adding missing column '
          '${column.name}',
        );
        await db.execute(
          'ALTER TABLE ${asset.tableName} ADD COLUMN ${column.definition}',
        );
      }
    } finally {
      await db.execute('DROP TABLE IF EXISTS $probe');
    }
  }

  static Future<List<_Column>> _columns(Database db, String table) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    return rows.map(_Column.fromPragmaRow).toList();
  }

  static Future<bool> _tableExists(Database db, String table) async {
    final result = await db.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1",
      [table],
    );
    return result.isNotEmpty;
  }
}

/// One column as `PRAGMA table_info` reports it.
class _Column {
  const _Column({
    required this.name,
    required this.type,
    required this.notNull,
    required this.defaultValue,
    required this.primaryKey,
  });

  factory _Column.fromPragmaRow(Map<String, Object?> row) => _Column(
    name: row['name'] as String,
    type: (row['type'] as String?) ?? '',
    notNull: (row['notnull'] as int? ?? 0) != 0,
    // Comes back as the literal SQL text ("0", "'commonName'"), which is what
    // an ALTER needs — not a parsed Dart value.
    defaultValue: row['dflt_value'] as String?,
    primaryKey: (row['pk'] as int? ?? 0) != 0,
  );

  final String name;
  final String type;
  final bool notNull;
  final String? defaultValue;
  final bool primaryKey;

  /// Whether `ALTER TABLE … ADD COLUMN` can give this column to a table that
  /// already exists.
  ///
  /// SQLite refuses two kinds: a `NOT NULL` column with no default (there is
  /// no value for the rows already there) and a primary-key column (the key
  /// is fixed when the table is created). Neither is a problem for the
  /// original columns of a table — a table that exists was created with them.
  /// It is only a problem for a column added to an asset later, which is what
  /// reconciliation exists to deliver.
  bool get canBeAdded => !primaryKey && (!notNull || defaultValue != null);

  String get notAddableReason =>
      primaryKey ? 'part of the primary key' : 'NOT NULL without a default';

  /// The column as an `ALTER TABLE … ADD COLUMN` needs to spell it.
  String get definition {
    final parts = <String>[name, if (type.isNotEmpty) type];
    if (notNull) parts.add('NOT NULL');
    if (defaultValue != null) parts.add('DEFAULT $defaultValue');
    return parts.join(' ');
  }
}
