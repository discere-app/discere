import 'dart:io';
import 'dart:math';

import 'package:discere/catalog/model/search_result.dart';
import 'package:discere/catalog/model/search_run.dart';
import 'package:discere/catalog/model/taxon_rank.dart';
import 'package:discere/catalog/model/taxonomy_detail.dart';
import 'package:discere/catalog/repository/search_repository.dart';
import 'package:discere/catalog/repository/species_repository.dart';
import 'package:discere/catalog/repository/taxonomy_repository.dart';
import 'package:discere/catalog/search/search_worker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// How the repositories read the reference database's rank placeholders
/// ([TaxonPlaceholderSql]), against the curated fixture: Kynaria cynara sits
/// under the family "Not assigned" in the order Nudibranchia, Elimia ornata
/// under the order "Not assigned" in the class Gastropoda.
const _kynariaCynara = 'discere:species:92182';
const _elimiaOrnata = 'discere:species:36817';
const _carcharodonCarcharias = 'discere:species:694';
const _unassignedFamily = 'discere:family:5210';
const _unassignedOrder = 'discere:order:719';
const _nudibranchia = 'discere:order:362';

SearchResult _taxon(String id, SearchEntityType type) =>
    SearchResult(id: id, name: '', commonNames: const {}, type: type);

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database referenceDb;
  late String referenceDbPath;

  Future<void> openFixture({required bool withPlaceholderColumn}) async {
    final suffix =
        '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(10000)}';
    referenceDbPath = join(
      Directory.systemTemp.path,
      'placeholder_reference_$suffix.db',
    );
    await File(referenceDbPath).writeAsBytes(
      await File('test/fixtures/discere_reference_test.db').readAsBytes(),
      flush: true,
    );
    referenceDb = await openDatabase(referenceDbPath);
    if (!withPlaceholderColumn) {
      // The shape of a reference database built before the column existed.
      for (final table in ['classes', 'orders', 'families', 'genera']) {
        await referenceDb.execute(
          'ALTER TABLE $table DROP COLUMN is_placeholder',
        );
      }
    }
  }

  tearDown(() async {
    await referenceDb.close();
    final file = File(referenceDbPath);
    if (file.existsSync()) await file.delete();
  });

  group('a reference database with the placeholder column', () {
    setUp(() => openFixture(withPlaceholderColumn: true));

    test('a species knows which ranks of its chain are placeholders', () async {
      final repository = SpeciesRepository(database: referenceDb);
      final species = {
        for (final s in await repository.getSpecies({
          _kynariaCynara,
          _elimiaOrnata,
          _carcharodonCarcharias,
        }))
          s.id: s,
      };

      expect(species[_kynariaCynara]!.classification.placeholderRanks, {
        TaxonRank.family,
      });
      expect(species[_elimiaOrnata]!.classification.placeholderRanks, {
        TaxonRank.order,
      });
      expect(
        species[_carcharodonCarcharias]!.classification.placeholderRanks,
        isEmpty,
      );
      final single = await repository.getSpeciesById(_kynariaCynara);
      expect(single!.classification.isPlaceholder(TaxonRank.family), isTrue);
    });

    test('a taxonomy page knows its own taxon is a placeholder', () async {
      final repository = TaxonomyRepository(database: referenceDb);

      final placeholder = await repository.getDetail(
        _taxon(_unassignedFamily, SearchEntityType.family),
      );
      final real = await repository.getDetail(
        _taxon(_nudibranchia, SearchEntityType.order),
      );

      expect(placeholder.isPlaceholder, isTrue);
      expect(real.isPlaceholder, isFalse);
    });

    test('a taxonomy page marks the placeholders above it', () async {
      final repository = TaxonomyRepository(database: referenceDb);
      final species = await SpeciesRepository(
        database: referenceDb,
      ).getSpeciesById(_kynariaCynara);

      final genus = await repository.getDetail(
        _taxon(species!.classification.genusId!, SearchEntityType.genus),
      );

      expect(
        genus.classification.map(
          (entry) => (entry.label, entry.id, entry.isPlaceholder),
        ),
        containsAllInOrder([
          (TaxonomyRankLabel.family, _unassignedFamily, true),
          (TaxonomyRankLabel.order, _nudibranchia, false),
        ]),
      );
    });

    test('a placeholder stays a child to navigate through', () async {
      final repository = TaxonomyRepository(database: referenceDb);

      final families = await repository.getChildren(
        _taxon(_nudibranchia, SearchEntityType.order),
      );
      final species = await repository.getChildren(
        _taxon(_unassignedOrder, SearchEntityType.order),
      );

      final placeholder = families.singleWhere(
        (family) => family.id == _unassignedFamily,
      );
      expect(placeholder.isPlaceholder, isTrue);
      expect(
        families.where((family) => family.id != _unassignedFamily),
        everyElement(
          isA<SearchResult>().having((f) => f.isPlaceholder, 'placeholder', false),
        ),
      );
      expect(species, isNotEmpty, reason: 'the order still leads down');
    });

    // The host's SQLite has no FTS4, so the fixture's FTS query fails over to
    // the LIKE fallback here; the FTS query's own filter is checked on its
    // text in search_sql_test.dart.
    test('search finds no placeholder', () async {
      final repository = SearchRepository(
        searchWorker: SearchWorker(),
        database: referenceDb,
      );

      for (final term in ['Not assigned', 'not']) {
        final ids = (await repository.searchAll(
          term,
          run: SearchRun.single,
        )).map((result) => result.id);
        expect(ids, isNot(contains(_unassignedFamily)), reason: term);
        expect(ids, isNot(contains(_unassignedOrder)), reason: term);
      }
      final real = await repository.searchAll(
        'Nudibranchia',
        run: SearchRun.single,
      );
      expect(real.map((result) => result.id), contains(_nudibranchia));
    });
  });

  group('a reference database without the placeholder column', () {
    setUp(() => openFixture(withPlaceholderColumn: false));

    test('loads species, pages, children and search as before', () async {
      final species = await SpeciesRepository(
        database: referenceDb,
      ).getSpeciesById(_kynariaCynara);
      final taxonomy = TaxonomyRepository(database: referenceDb);
      final detail = await taxonomy.getDetail(
        _taxon(_unassignedFamily, SearchEntityType.family),
      );
      final children = await taxonomy.getChildren(
        _taxon(_nudibranchia, SearchEntityType.order),
      );
      final found = await SearchRepository(
        searchWorker: SearchWorker(),
        database: referenceDb,
      ).searchAll('Not assigned', run: SearchRun.single);

      // Nothing is marked: such a database shows its placeholders under the
      // source's name, as it always did.
      expect(species!.classification.placeholderRanks, isEmpty);
      expect(species.classification.familyScientificName, 'Not assigned');
      expect(detail.isReferenceBacked, isTrue);
      expect(detail.isPlaceholder, isFalse);
      expect(children.map((child) => child.id), contains(_unassignedFamily));
      expect(children.where((child) => child.isPlaceholder), isEmpty);
      expect(found.map((result) => result.id), contains(_unassignedFamily));
    });
  });
}
