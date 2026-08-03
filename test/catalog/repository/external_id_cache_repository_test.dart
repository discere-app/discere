import 'dart:io';
import 'dart:math';

import 'package:discere/catalog/model/external_id_provider.dart';
import 'package:discere/catalog/repository/external_id_cache_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late String dbPath;
  late ExternalIdCacheRepository repository;

  setUp(() async {
    final tempDir = Directory.systemTemp;
    final suffix =
        '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(10000)}';
    dbPath = join(tempDir.path, 'external_id_cache_$suffix.db');
    db = await openDatabase(dbPath);
    await db.execute('''
      CREATE TABLE external_identifier_cache (
        entity_id TEXT NOT NULL,
        provider TEXT NOT NULL,
        external_id TEXT NOT NULL,
        PRIMARY KEY (entity_id, provider)
      )
    ''');
    repository = ExternalIdCacheRepository(database: db);
  });

  tearDown(() async {
    await db.close();
    final file = File(dbPath);
    if (await file.exists()) {
      await file.delete();
    }
  });

  Future<void> insertCacheEntry(
    String entityId,
    ExternalIdProvider provider,
    String value,
  ) {
    return db.insert('external_identifier_cache', {
      'entity_id': entityId,
      'provider': provider.name,
      'external_id': value,
    });
  }

  group('getRawExternalIdsForProvider', () {
    test('returns an empty map for an empty id set', () async {
      final result = await repository.getRawExternalIdsForProvider(
        {},
        ExternalIdProvider.iucnStatus,
      );

      expect(result, isEmpty);
    });

    test('returns cached raw string values keyed by entity id', () async {
      await insertCacheEntry('sp1', ExternalIdProvider.iucnStatus, 'lc');
      await insertCacheEntry('sp2', ExternalIdProvider.iucnStatus, 'en');

      final result = await repository.getRawExternalIdsForProvider({
        'sp1',
        'sp2',
      }, ExternalIdProvider.iucnStatus);

      expect(result, {'sp1': 'lc', 'sp2': 'en'});
    });

    test('omits entities without a cache entry', () async {
      await insertCacheEntry('sp1', ExternalIdProvider.iucnStatus, 'lc');

      final result = await repository.getRawExternalIdsForProvider({
        'sp1',
        'sp2',
      }, ExternalIdProvider.iucnStatus);

      expect(result, {'sp1': 'lc'});
    });

    test('only matches the requested provider', () async {
      await insertCacheEntry('sp1', ExternalIdProvider.wikipedia, 'https://x');

      final result = await repository.getRawExternalIdsForProvider({
        'sp1',
      }, ExternalIdProvider.iucnStatus);

      expect(result, isEmpty);
    });
  });
}
