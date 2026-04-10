import 'dart:io';
import 'dart:math';

import 'package:discere/model/language.dart';
import 'package:discere/model/search/search_result.dart';
import 'package:discere/persistence/taxonomy_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<
  (
    Database referenceDb,
    Database userDb,
    String referenceDbPath,
    String userDbPath,
  )
>
initializeDatabases() async {
  final tempDir = Directory.systemTemp;
  final suffix =
      '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(10000)}';
  final referenceDbPath = join(tempDir.path, 'taxonomy_reference_$suffix.db');
  final userDbPath = join(tempDir.path, 'taxonomy_user_$suffix.db');

  final referenceDb = await openDatabase(referenceDbPath);
  final userDb = await openDatabase(userDbPath);

  await referenceDb.execute('''
    CREATE TABLE classes (
      id TEXT PRIMARY KEY,
      name TEXT,
      common_name TEXT,
      body_shape TEXT,
      super_class TEXT
    )
  ''');
  await referenceDb.execute('''
    CREATE TABLE orders (
      id TEXT PRIMARY KEY,
      name TEXT,
      common_name_de TEXT,
      common_name_en TEXT,
      common_name_fr TEXT,
      common_name_es TEXT,
      sister_order TEXT,
      class TEXT
    )
  ''');
  await referenceDb.execute('''
    CREATE TABLE families (
      id TEXT PRIMARY KEY,
      name TEXT,
      common_name_de TEXT,
      common_name_en TEXT,
      common_name_fr TEXT,
      common_name_es TEXT,
      body_shape TEXT,
      division TEXT,
      "order" TEXT
    )
  ''');
  await referenceDb.execute('''
    CREATE TABLE genera (
      id TEXT PRIMARY KEY,
      name TEXT,
      common_name TEXT,
      subfamily TEXT,
      body_shape TEXT,
      family TEXT
    )
  ''');
  await referenceDb.execute('''
    CREATE TABLE species (
      id TEXT PRIMARY KEY,
      genus TEXT,
      status TEXT
    )
  ''');

  await referenceDb.insert('classes', {
    'id': 'class-1',
    'name': 'Chondrichthyes',
    'common_name': 'Cartilaginous fishes',
    'body_shape': 'streamlined',
    'super_class': 'Vertebrata',
  });
  await referenceDb.insert('orders', {
    'id': 'order-1',
    'name': 'Lamniformes',
    'common_name_en': 'Mackerel sharks',
    'sister_order': 'Testiformes',
    'class': 'class-1',
  });
  await referenceDb.insert('families', {
    'id': 'family-1',
    'name': 'Lamnidae',
    'common_name_en': 'Mackerel sharks',
    'body_shape': 'compressed',
    'division': 'Teleostei',
    'order': 'order-1',
  });
  await referenceDb.insert('genera', {
    'id': 'genus-1',
    'name': 'Carcharodon',
    'common_name': 'White sharks',
    'subfamily': 'Testinae',
    'body_shape': 'fusiform',
    'family': 'family-1',
  });
  await referenceDb.insert('species', {
    'id': 'species-1',
    'genus': 'genus-1',
    'status': 'active',
  });

  await userDb.execute('''
    CREATE TABLE runtime_common_names (
      entity_key     TEXT NOT NULL,
      entity_type    TEXT NOT NULL,
      language_code  TEXT NOT NULL,
      names          TEXT NOT NULL,
      fetched_at     INTEGER NOT NULL,
      PRIMARY KEY (entity_key, language_code)
    )
  ''');

  return (referenceDb, userDb, referenceDbPath, userDbPath);
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database referenceDb;
  late Database userDb;
  late String referenceDbPath;
  late String userDbPath;
  late TaxonomyRepository repository;

  setUp(() async {
    final dbs = await initializeDatabases();
    referenceDb = dbs.$1;
    userDb = dbs.$2;
    referenceDbPath = dbs.$3;
    userDbPath = dbs.$4;
    repository = TaxonomyRepository(
      database: referenceDb,
      userDatabase: userDb,
    );
  });

  tearDown(() async {
    await referenceDb.close();
    await userDb.close();
    final referenceFile = File(referenceDbPath);
    if (await referenceFile.exists()) {
      await referenceFile.delete();
    }
    final userFile = File(userDbPath);
    if (await userFile.exists()) {
      await userFile.delete();
    }
  });

  test('maps taxonomy attributes for genus, family, order and class', () async {
    final genusDetail = await repository.getDetail(
      SearchResult(
        id: 'genus-1',
        name: 'Carcharodon',
        commonNames: const {Language.en: null},
        type: SearchEntityType.genus,
      ),
    );
    final familyDetail = await repository.getDetail(
      SearchResult(
        id: 'family-1',
        name: 'Lamnidae',
        commonNames: const {Language.en: null},
        type: SearchEntityType.family,
      ),
    );
    final orderDetail = await repository.getDetail(
      SearchResult(
        id: 'order-1',
        name: 'Lamniformes',
        commonNames: const {Language.en: null},
        type: SearchEntityType.order,
      ),
    );
    final classDetail = await repository.getDetail(
      SearchResult(
        id: 'class-1',
        name: 'Chondrichthyes',
        commonNames: const {Language.en: null},
        type: SearchEntityType.classType,
      ),
    );

    expect(
      genusDetail.attributes.map((attribute) => attribute.key),
      containsAll(['subfamily', 'body_shape']),
    );
    expect(
      familyDetail.attributes.map((attribute) => attribute.key),
      containsAll(['body_shape', 'division']),
    );
    expect(orderDetail.attributes.single.value, 'Testiformes');
    expect(classDetail.attributes.single.value, 'streamlined');
  });
}
