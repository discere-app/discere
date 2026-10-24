import 'package:discere/catalog/model/taxon_rank.dart';
import 'package:discere/catalog/repository/inat_allowed_ancestor_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// iNaturalist ids: Mollusca, Arthropoda, Gastropoda.
const _mollusca = 47115;
const _arthropoda = 47120;
const _gastropoda = 47114;

void main() {
  late Database db;

  setUp(() async {
    sqfliteFfiInit();
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await db.execute('CREATE TABLE classes (id TEXT, name TEXT)');
    await db.execute('CREATE TABLE orders (id TEXT, name TEXT, class TEXT)');
    await db.execute(
      'CREATE TABLE families (id TEXT, name TEXT, "order" TEXT)',
    );
    await db.execute('CREATE TABLE genera (id TEXT, name TEXT, family TEXT)');
    await db.execute('CREATE TABLE species (id TEXT, genus TEXT)');
    // Two classes: snails and crustaceans; the genus Apus in both, and once
    // more without a chain and without species.
    await db.execute('''
      INSERT INTO classes VALUES ('c:snails', 'Gastropoda'),
                                 ('c:crustaceans', 'Branchiopoda')''');
    await db.execute('''
      INSERT INTO orders VALUES ('o:snails', 'Littorinimorpha', 'c:snails'),
                                ('o:crustaceans', 'Notostraca', 'c:crustaceans')''');
    await db.execute('''
      INSERT INTO families VALUES ('f:snails', 'Triphoridae', 'o:snails'),
                                  ('f:crustaceans', 'Triopsidae', 'o:crustaceans')''');
    await db.execute('''
      INSERT INTO genera VALUES ('g:triphora', 'Triphora', 'f:snails'),
                                ('g:apus-snail', 'Apus', 'f:snails'),
                                ('g:apus-crustacean', 'Apus', 'f:crustaceans'),
                                ('g:apus-empty', 'Apus', NULL),
                                ('g:loose', 'Loosia', NULL)''');
    await db.execute('''
      INSERT INTO species VALUES ('s:1', 'g:triphora'),
                                 ('s:2', 'g:apus-snail'),
                                 ('s:3', 'g:apus-crustacean'),
                                 ('s:4', 'g:loose')''');
  });

  tearDown(() => db.close());

  Future<void> createAllowedAncestors() async {
    await db.execute(
      'CREATE TABLE ${INatAllowedAncestorRepository.tableName} '
      '(class_id TEXT, rank TEXT, inat_taxon_id INTEGER)',
    );
    await db.execute('''
      INSERT INTO ${INatAllowedAncestorRepository.tableName} VALUES
        ('c:snails', 'phylum', $_mollusca),
        ('c:snails', 'class', $_gastropoda),
        ('c:crustaceans', 'phylum', $_arthropoda)''');
  }

  group('INatAllowedAncestorRepository', () {
    test('a species requires a phylum of its class', () async {
      await createAllowedAncestors();
      final repository = INatAllowedAncestorRepository(referenceDatabase: db);

      final requirement = await repository.requirementForSpecies('c:snails');

      expect(requirement?.anyOf, [
        {_mollusca},
      ]);
    });

    test('a species without a class cannot be checked', () async {
      await createAllowedAncestors();
      final repository = INatAllowedAncestorRepository(referenceDatabase: db);

      final requirement = await repository.requirementForSpecies(null);

      expect(requirement?.canBeMet, isFalse);
    });

    test('a genus requires phylum and class of its class', () async {
      await createAllowedAncestors();
      final repository = INatAllowedAncestorRepository(referenceDatabase: db);

      final requirement = await repository.requirementForHigherTaxon(
        TaxonRank.genus,
        'Triphora',
      );

      expect(requirement?.anyOf, [
        {_mollusca},
        {_gastropoda},
      ]);
      expect(requirement?.isMetBy([1, _mollusca, _gastropoda, 9]), isTrue);
    });

    test('a name key carried by rows of two classes must fit each — a row '
        'without species does not count', () async {
      await createAllowedAncestors();
      final repository = INatAllowedAncestorRepository(referenceDatabase: db);

      final requirement = await repository.requirementForHigherTaxon(
        TaxonRank.genus,
        'apus',
      );

      expect(requirement?.anyOf, hasLength(4));
      // The crustaceans' class has no iNaturalist class to check against.
      expect(requirement?.canBeMet, isFalse);
    });

    test('a row without a chain up to its class cannot be checked', () async {
      await createAllowedAncestors();
      final repository = INatAllowedAncestorRepository(referenceDatabase: db);

      final requirement = await repository.requirementForHigherTaxon(
        TaxonRank.genus,
        'Loosia',
      );

      expect(requirement?.canBeMet, isFalse);
    });

    test('a class requires only a phylum', () async {
      await createAllowedAncestors();
      final repository = INatAllowedAncestorRepository(referenceDatabase: db);

      final requirement = await repository.requirementForHigherTaxon(
        TaxonRank.classRank,
        'Branchiopoda',
      );

      expect(requirement?.anyOf, [
        {_arthropoda},
      ]);
    });

    test('an order and a family are found through their class', () async {
      await createAllowedAncestors();
      final repository = INatAllowedAncestorRepository(referenceDatabase: db);

      expect(
        (await repository.requirementForHigherTaxon(
          TaxonRank.order,
          'Littorinimorpha',
        ))?.anyOf,
        [
          {_mollusca},
          {_gastropoda},
        ],
      );
      expect(
        (await repository.requirementForHigherTaxon(
          TaxonRank.family,
          'Triphoridae',
        ))?.anyOf,
        [
          {_mollusca},
          {_gastropoda},
        ],
      );
    });

    test('says nothing for a reference database without the table', () async {
      final repository = INatAllowedAncestorRepository(referenceDatabase: db);

      expect(await repository.requirementForSpecies('c:snails'), isNull);
      expect(
        await repository.requirementForHigherTaxon(TaxonRank.genus, 'Apus'),
        isNull,
      );
    });
  });
}
