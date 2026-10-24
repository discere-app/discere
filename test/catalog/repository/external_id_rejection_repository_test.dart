import 'package:discere/catalog/model/external_id_provider.dart';
import 'package:discere/catalog/repository/external_id_rejection_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;

  setUp(() async {
    sqfliteFfiInit();
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
  });

  tearDown(() => db.close());

  test('knows the entities the ETL rejected, per provider', () async {
    await db.execute(
      'CREATE TABLE ${ExternalIdRejectionRepository.tableName} '
      '(entity_id TEXT, entity_type TEXT, provider TEXT, reason TEXT)',
    );
    await db.execute('''
      INSERT INTO ${ExternalIdRejectionRepository.tableName} VALUES
        ('s:1', 'species', 'inaturalist', 'phylum_mismatch'),
        ('genus:apus', 'genera', 'inaturalist', 'phylum_mixed')''');
    final repository = ExternalIdRejectionRepository(referenceDatabase: db);

    expect(
      await repository.isRejected('s:1', ExternalIdProvider.inaturalist),
      isTrue,
    );
    expect(
      await repository.isRejected(
        'genus:apus',
        ExternalIdProvider.inaturalist,
      ),
      isTrue,
    );
    expect(
      await repository.isRejected('s:2', ExternalIdProvider.inaturalist),
      isFalse,
    );
    expect(
      await repository.isRejected('s:1', ExternalIdProvider.wikipedia),
      isFalse,
    );
  });

  test('knows of no rejection in a reference database without the table', () async {
    final repository = ExternalIdRejectionRepository(referenceDatabase: db);

    expect(
      await repository.isRejected('s:1', ExternalIdProvider.inaturalist),
      isFalse,
    );
  });
}
