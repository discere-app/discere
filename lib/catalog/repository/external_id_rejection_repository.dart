import 'package:discere/catalog/model/external_id_provider.dart';
import 'package:discere/catalog/repository/optional_reference_table.dart';
import 'package:discere/shared/persistence/database_helper.dart';
import 'package:sqflite/sqflite.dart';

/// Which entities the ETL deliberately gave no external id: their name hits
/// a taxon that does not fit their chain, cannot be checked, or is not the
/// only one that fits.
///
/// A runtime search by the same name would find the same taxa again and
/// check them less thoroughly than the ETL did, so for these entities there
/// is no search at all. Keyed like `entity_external_ids`: the species id, or
/// the name key of a higher taxon (`genus:megalomma`).
///
/// A reference database without the table knows of no rejection.
class ExternalIdRejectionRepository {
  static const tableName = 'entity_external_id_rejections';

  /// Entity keys bound per batched lookup, below SQLite's 999-variable limit.
  static const _maxKeysPerQuery = 500;

  final Database? _injectedRefDb;

  ExternalIdRejectionRepository({Database? referenceDatabase})
    : _injectedRefDb = referenceDatabase;

  Future<Database> get _referenceDb async =>
      _injectedRefDb ?? await DatabaseHelper.referenceDb;

  Future<bool> isRejected(
    String entityKey,
    ExternalIdProvider provider,
  ) async => (await rejectedAmong({entityKey}, provider)).isNotEmpty;

  /// Those of [entityKeys] the ETL rejected for [provider].
  Future<Set<String>> rejectedAmong(
    Set<String> entityKeys,
    ExternalIdProvider provider,
  ) async {
    if (entityKeys.isEmpty) return const {};
    final db = await _referenceDb;
    if (!await OptionalReferenceTable.exists(db, tableName)) return const {};
    final keys = entityKeys.toList();
    final rejected = <String>{};
    for (var i = 0; i < keys.length; i += _maxKeysPerQuery) {
      final chunk = keys.skip(i).take(_maxKeysPerQuery).toList();
      final rows = await db.rawQuery(
        'SELECT DISTINCT entity_id FROM $tableName WHERE provider = ? '
        'AND entity_id IN (${List.filled(chunk.length, '?').join(', ')})',
        [provider.name, ...chunk],
      );
      rejected.addAll([for (final row in rows) row['entity_id'] as String]);
    }
    return rejected;
  }
}
