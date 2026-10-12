import 'package:discere/catalog/model/external_id_provider.dart';
import 'package:discere/catalog/repository/external_id_repository.dart';
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

  Future<void> createTable() async {
    await db.execute(
      'CREATE TABLE ${ExternalIdRepository.tableName} ('
      'entity_id TEXT, provider TEXT, external_id TEXT)',
    );
    await db.insert(ExternalIdRepository.tableName, {
      'entity_id': 'sp-1',
      'provider': ExternalIdProvider.inaturalist.name,
      'external_id': '47',
    });
  }

  final failedRead = isA<DatabaseException>().having(
    (e) => e.isNoSuchTableError(ExternalIdRepository.tableName),
    'isNoSuchTableError',
    isTrue,
  );

  test('reads the reference id of one entity and of a batch', () async {
    await createTable();
    final repository = ExternalIdRepository(referenceDatabase: db);

    expect(
      await repository.getExternalId('sp-1', ExternalIdProvider.inaturalist),
      '47',
    );
    expect(
      await repository.getExternalIdsForProvider({
        'sp-1',
        'sp-2',
      }, ExternalIdProvider.inaturalist),
      {'sp-1': 47},
    );
  });

  test('a read that fails propagates instead of answering "no id"', () async {
    final repository = ExternalIdRepository(referenceDatabase: db);

    await expectLater(
      repository.getExternalId('sp-1', ExternalIdProvider.inaturalist),
      throwsA(failedRead),
    );
    await expectLater(
      repository.getExternalIdsForProvider({
        'sp-1',
      }, ExternalIdProvider.inaturalist),
      throwsA(failedRead),
    );
  });
}
