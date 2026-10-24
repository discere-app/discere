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

/// A species whose chain of higher ranks breaks off still loads, against a
/// copy of the curated fixture with two gaps cut into it: Carcharodon
/// carcharias loses its genus, and the genus Amphiprion loses its family.
/// Without its genus, Carcharodon carcharias keeps the preferred scientific
/// name its source (FishBase) gives it, "Carcharodon carcharias".
const _carcharodonCarcharias = 'discere:species:694';
const _amphiprionOcellaris = 'discere:species:6002';
const _amphiprion = 'discere:genus:5106';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database referenceDb;
  late String referenceDbPath;

  setUp(() async {
    final suffix =
        '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(10000)}';
    referenceDbPath = join(
      Directory.systemTemp.path,
      'broken_chain_reference_$suffix.db',
    );
    await File(referenceDbPath).writeAsBytes(
      await File('test/fixtures/discere_reference_test.db').readAsBytes(),
      flush: true,
    );
    referenceDb = await openDatabase(referenceDbPath);
    await referenceDb.update(
      'species',
      {'genus': null},
      where: 'id = ?',
      whereArgs: [_carcharodonCarcharias],
    );
    await referenceDb.update(
      'genera',
      {'family': null},
      where: 'id = ?',
      whereArgs: [_amphiprion],
    );
  });

  tearDown(() async {
    await referenceDb.close();
    final file = File(referenceDbPath);
    if (file.existsSync()) await file.delete();
  });

  test('a species without a genus loads, with no rank above it', () async {
    final species = await SpeciesRepository(
      database: referenceDb,
    ).getSpeciesById(_carcharodonCarcharias);

    expect(species, isNotNull);
    final classification = species!.classification;
    expect(classification.genusScientificName, isNull);
    expect(classification.genusId, isNull);
    expect(classification.classScientificName, isNull);
    expect(classification.unassignedRanks, TaxonRank.values.toSet());
  });

  test('a species without a genus is named by its preferred scientific '
      'name', () async {
    final repository = SpeciesRepository(database: referenceDb);

    final byId = await repository.getSpeciesById(_carcharodonCarcharias);
    final inBatch = await repository.getSpecies({_carcharodonCarcharias});

    expect(byId!.binomialName, 'Carcharodon carcharias');
    expect(inBatch.single.binomialName, 'Carcharodon carcharias');
  });

  test('the preferred name from the species\' own source outranks one from '
      'another source', () async {
    // "catalogue" sorts before "fishbase", the species' own source.
    await referenceDb.insert('species_scientific_names', {
      'species_id': _carcharodonCarcharias,
      'name': 'Carcharias albus',
      'normalized_name': 'carcharias albus',
      'name_status': 'valid',
      'source': 'catalogue',
      'is_preferred': 1,
    });

    final species = await SpeciesRepository(
      database: referenceDb,
    ).getSpeciesById(_carcharodonCarcharias);

    expect(species!.binomialName, 'Carcharodon carcharias');
  });

  test('a species without a genus or a preferred name is named by its '
      'epithet', () async {
    await referenceDb.update(
      'species_scientific_names',
      {'is_preferred': 0},
      where: 'species_id = ?',
      whereArgs: [_carcharodonCarcharias],
    );

    final species = await SpeciesRepository(
      database: referenceDb,
    ).getSpeciesById(_carcharodonCarcharias);

    expect(species!.binomialName, isNull);
    expect(species.getBinomialName(), 'carcharias');
  });

  test('a batch keeps species whose chain breaks off at any rank', () async {
    final species = {
      for (final s in await SpeciesRepository(
        database: referenceDb,
      ).getSpecies({_carcharodonCarcharias, _amphiprionOcellaris}))
        s.id: s,
    };

    expect(species.keys, {_carcharodonCarcharias, _amphiprionOcellaris});
    final ocellaris = species[_amphiprionOcellaris]!.classification;
    expect(ocellaris.genusScientificName, 'Amphiprion');
    expect(ocellaris.familyScientificName, isNull);
    expect(ocellaris.orderId, isNull);
    expect(ocellaris.unassignedRanks, {
      TaxonRank.family,
      TaxonRank.order,
      TaxonRank.classRank,
    });
    expect(
      species[_amphiprionOcellaris]!.getBinomialName(),
      'Amphiprion ocellaris',
    );
  });

  test(
    'the search finds a species without a genus under its epithet, named '
    'in full',
    () async {
      final found = await SearchRepository(
        searchWorker: SearchWorker(),
        database: referenceDb,
      ).searchAll('carcharias', run: SearchRun.single);

      final hit = found.singleWhere((r) => r.id == _carcharodonCarcharias);
      expect(hit.name, 'Carcharodon carcharias');
    },
  );

  test(
    'the search finds a species without a genus by its preferred name',
    () async {
      // No FTS table holds a full species name, so this term reaches the
      // LIKE fallback, which matches the name as shown.
      final found = await SearchRepository(
        searchWorker: SearchWorker(),
        database: referenceDb,
      ).searchAll('Carcharodon carch', run: SearchRun.single);

      final hit = found.singleWhere((r) => r.id == _carcharodonCarcharias);
      expect(hit.name, 'Carcharodon carcharias');
    },
  );

  test('a genus page lists the ranks its chain does not reach as '
      'unassigned', () async {
    final detail = await TaxonomyRepository(database: referenceDb).getDetail(
      SearchResult(
        id: _amphiprion,
        name: 'Amphiprion',
        commonNames: const {},
        type: SearchEntityType.genus,
      ),
    );

    expect(
      detail.classification.map((entry) => (entry.label, entry.isUnassigned)),
      [
        (TaxonomyRankLabel.family, true),
        (TaxonomyRankLabel.order, true),
        (TaxonomyRankLabel.classType, true),
      ],
    );
  });
}
