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

  final Database? _injectedRefDb;

  ExternalIdRejectionRepository({Database? referenceDatabase})
    : _injectedRefDb = referenceDatabase;

  Future<Database> get _referenceDb async =>
      _injectedRefDb ?? await DatabaseHelper.referenceDb;

  Future<bool> isRejected(String entityKey, ExternalIdProvider provider) async {
    final db = await _referenceDb;
    if (!await OptionalReferenceTable.exists(db, tableName)) return false;
    final rows = await db.query(
      tableName,
      columns: ['entity_id'],
      where: 'entity_id = ? AND provider = ?',
      whereArgs: [entityKey, provider.name],
      limit: 1,
    );
    return rows.isNotEmpty;
  }
}
