import 'dart:io';
import 'dart:math';

import 'package:discere/catalog/model/search_result.dart';
import 'package:discere/catalog/model/taxonomy_detail.dart';
import 'package:discere/catalog/repository/taxonomy_repository.dart';
import 'package:discere/shared/model/language.dart';
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
      name TEXT,
      status TEXT
    )
  ''');
  await referenceDb.execute('''
    CREATE TABLE common_names (
      entity_id TEXT NOT NULL,
      entity_type TEXT NOT NULL,
      language TEXT NOT NULL,
      country TEXT,
      name TEXT NOT NULL,
      source TEXT NOT NULL,
      rank INTEGER,
      is_preferred INTEGER NOT NULL DEFAULT 0,
      name_type TEXT
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
    'name': 'carcharias',
    'status': 'active',
  });
  await referenceDb.insert('common_names', {
    'entity_id': 'class-1',
    'entity_type': 'class',
    'language': 'en',
    'country': null,
    'name': 'Cartilaginous fishes',
    'source': 'test',
    'rank': 1,
    'is_preferred': 1,
    'name_type': null,
  });
  await referenceDb.insert('common_names', {
    'entity_id': 'order-1',
    'entity_type': 'order',
    'language': 'en',
    'country': null,
    'name': 'Mackerel sharks',
    'source': 'test',
    'rank': 1,
    'is_preferred': 1,
    'name_type': null,
  });
  await referenceDb.insert('common_names', {
    'entity_id': 'family-1',
    'entity_type': 'family',
    'language': 'en',
    'country': null,
    'name': 'Mackerel sharks',
    'source': 'test',
    'rank': 1,
    'is_preferred': 1,
    'name_type': null,
  });
  await referenceDb.insert('common_names', {
    'entity_id': 'genus-1',
    'entity_type': 'genus',
    'language': 'en',
    'country': null,
    'name': 'White sharks',
    'source': 'test',
    'rank': 1,
    'is_preferred': 1,
    'name_type': null,
  });

  await userDb.execute('''
    CREATE TABLE runtime_common_names (
      entity_key     TEXT NOT NULL,
      entity_type    TEXT NOT NULL,
      language_code  TEXT NOT NULL,
      name           TEXT NOT NULL,
      position       INTEGER,
      place_id       INTEGER,
      place_position INTEGER,
      fetched_at     INTEGER NOT NULL,
      PRIMARY KEY (entity_key, language_code, name, place_id)
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
        commonNames: const {Language.en: []},
        type: SearchEntityType.genus,
      ),
    );
    final familyDetail = await repository.getDetail(
      SearchResult(
        id: 'family-1',
        name: 'Lamnidae',
        commonNames: const {Language.en: []},
        type: SearchEntityType.family,
      ),
    );
    final orderDetail = await repository.getDetail(
      SearchResult(
        id: 'order-1',
        name: 'Lamniformes',
        commonNames: const {Language.en: []},
        type: SearchEntityType.order,
      ),
    );
    final classDetail = await repository.getDetail(
      SearchResult(
        id: 'class-1',
        name: 'Chondrichthyes',
        commonNames: const {Language.en: []},
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

  test('returns family genera and genus species using reference ids', () async {
    final familyChildren = await repository.getChildren(
      SearchResult(
        id: 'family-1',
        name: 'Lamnidae',
        commonNames: const {},
        type: SearchEntityType.family,
      ),
    );

    expect(familyChildren, hasLength(1));
    expect(familyChildren.single.id, 'genus-1');
    expect(familyChildren.single.type, SearchEntityType.genus);

    final genusChildren = await repository.getChildren(familyChildren.single);

    expect(genusChildren, hasLength(1));
    expect(genusChildren.single.id, 'species-1');
    expect(genusChildren.single.name, 'Carcharodon carcharias');
    expect(genusChildren.single.type, SearchEntityType.species);
  });

  test('returns orders for a class', () async {
    final children = await repository.getChildren(
      SearchResult(
        id: 'class-1',
        name: 'Chondrichthyes',
        commonNames: const {},
        type: SearchEntityType.classType,
      ),
    );

    expect(children, hasLength(1));
    expect(children.single.id, 'order-1');
    expect(children.single.type, SearchEntityType.order);
  });

  test('returns families for an order', () async {
    final children = await repository.getChildren(
      SearchResult(
        id: 'order-1',
        name: 'Lamniformes',
        commonNames: const {},
        type: SearchEntityType.order,
      ),
    );

    expect(children, hasLength(1));
    expect(children.single.id, 'family-1');
    expect(children.single.type, SearchEntityType.family);
  });

  test('returns empty list for species (leaf nodes have no children)', () async {
    final children = await repository.getChildren(
      SearchResult(
        id: 'species-1',
        name: 'Carcharodon carcharias',
        commonNames: const {},
        type: SearchEntityType.species,
      ),
    );

    expect(children, isEmpty);
  });

  test('returns empty list for inat:-prefixed ids without a DB lookup', () async {
    final children = await repository.getChildren(
      SearchResult(
        id: 'inat:12345',
        name: 'Carcharodon',
        commonNames: const {},
        type: SearchEntityType.genus,
      ),
    );

    expect(children, isEmpty);
  });

  test('omits inactive species from genus children', () async {
    await referenceDb.insert('species', {
      'id': 'species-inactive',
      'genus': 'genus-1',
      'name': 'antiquus',
      'status': 'inactive',
    });

    final children = await repository.getChildren(
      SearchResult(
        id: 'genus-1',
        name: 'Carcharodon',
        commonNames: const {},
        type: SearchEntityType.genus,
      ),
    );

    expect(children.map((c) => c.id), isNot(contains('species-inactive')));
    expect(children.map((c) => c.id), contains('species-1'));
  });

  test('family genera_count metric matches number of genera shown as children',
      () async {
    // genus-2 has no active species and must not inflate the genera_count metric
    await referenceDb.insert('genera', {
      'id': 'genus-empty',
      'name': 'Emptyus',
      'family': 'family-1',
    });

    final familyDetail = await repository.getDetail(
      SearchResult(
        id: 'family-1',
        name: 'Lamnidae',
        commonNames: const {},
        type: SearchEntityType.family,
      ),
    );
    final familyChildren = await repository.getChildren(
      SearchResult(
        id: 'family-1',
        name: 'Lamnidae',
        commonNames: const {},
        type: SearchEntityType.family,
      ),
    );

    final generaMetric = familyDetail.metrics
        .firstWhere((m) => m.type == TaxonomyMetricType.genera);
    expect(generaMetric.count, familyChildren.length,
        reason: 'genera_count metric must equal the number of visible genera');
    expect(generaMetric.count, 1);
    expect(familyChildren.map((c) => c.id), isNot(contains('genus-empty')));
  });

  test('order families_count and genera_count metrics match visible children',
      () async {
    // Add an empty family (no active species) to the order
    await referenceDb.insert('families', {
      'id': 'family-empty',
      'name': 'Emptyidae',
      'order': 'order-1',
    });
    await referenceDb.insert('genera', {
      'id': 'genus-in-empty-family',
      'name': 'Ghostus',
      'family': 'family-empty',
    });

    final orderDetail = await repository.getDetail(
      SearchResult(
        id: 'order-1',
        name: 'Lamniformes',
        commonNames: const {},
        type: SearchEntityType.order,
      ),
    );
    final orderChildren = await repository.getChildren(
      SearchResult(
        id: 'order-1',
        name: 'Lamniformes',
        commonNames: const {},
        type: SearchEntityType.order,
      ),
    );

    final familiesMetric = orderDetail.metrics
        .firstWhere((m) => m.type == TaxonomyMetricType.families);
    expect(familiesMetric.count, orderChildren.length,
        reason:
            'families_count metric must equal the number of visible families');
    expect(familiesMetric.count, 1);
    expect(orderChildren.map((c) => c.id), isNot(contains('family-empty')));
  });

  test('class metrics only count taxa with active species', () async {
    // Add an empty order chain: class-1 → order-empty → family-empty2 (no active species)
    await referenceDb.insert('orders', {
      'id': 'order-empty',
      'name': 'Ghostiformes',
      'class': 'class-1',
    });
    await referenceDb.insert('families', {
      'id': 'family-ghost',
      'name': 'Ghostidae',
      'order': 'order-empty',
    });
    await referenceDb.insert('genera', {
      'id': 'genus-ghost',
      'name': 'Ghostus',
      'family': 'family-ghost',
    });

    final classDetail = await repository.getDetail(
      SearchResult(
        id: 'class-1',
        name: 'Chondrichthyes',
        commonNames: const {},
        type: SearchEntityType.classType,
      ),
    );
    final classChildren = await repository.getChildren(
      SearchResult(
        id: 'class-1',
        name: 'Chondrichthyes',
        commonNames: const {},
        type: SearchEntityType.classType,
      ),
    );

    final ordersMetric = classDetail.metrics
        .firstWhere((m) => m.type == TaxonomyMetricType.orders);
    expect(ordersMetric.count, classChildren.length,
        reason: 'orders_count metric must equal the number of visible orders');
    expect(ordersMetric.count, 1);
    expect(classChildren.map((c) => c.id), isNot(contains('order-empty')));
  });
}
