import 'package:discere/enrichment/pipeline/repository/inat_photo_cache_repository.dart';
import 'package:discere/external/inaturalist/models/inat_photo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import '../../../support/in_memory_user_database.dart';

/// Covers INatPhotoCacheRepository's three-way answer per species — not
/// cached, cached-but-empty (the sentinel), cached with photos — and that the
/// batched read keeps it per species rather than collapsing a mixed batch into
/// one answer. A session resolves all its due cards through the batched read,
/// so a species whose state it got wrong would either re-trigger an iNat
/// lookup or hide photos the user already has.

INatPhoto _photo(String url) =>
    INatPhoto(url: url, attribution: 'someone', licenseCode: 'cc-by');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database database;
  late INatPhotoCacheRepository repository;

  setUp(() async {
    database = await openInMemoryUserDatabase();
    repository = INatPhotoCacheRepository(database: database);
  });

  tearDown(() async {
    await database.close();
  });

  test('a species that was never looked up is absent from the batch', () async {
    final cached = await repository.getCachedPhotosForSpecies({'sp1'});

    expect(cached.containsKey('sp1'), isFalse);
    expect(await repository.getCachedPhotos('sp1'), isNull);
  });

  test('a species looked up without photos maps to an empty list', () async {
    await repository.cachePhotos('sp1', [], taxonId: null);

    final cached = await repository.getCachedPhotosForSpecies({'sp1'});

    expect(cached['sp1'], isEmpty);
    expect(await repository.getCachedPhotos('sp1'), isEmpty);
  });

  test('a species with photos maps to its photos', () async {
    await repository.cachePhotos('sp1', [
      _photo('https://inat/a.jpg'),
      _photo('https://inat/b.jpg'),
    ], taxonId: 7);

    final cached = await repository.getCachedPhotosForSpecies({'sp1'});

    expect(cached['sp1'], hasLength(2));
    expect(
      cached['sp1']!.every((picture) => picture.species == 'sp1'),
      isTrue,
    );
  });

  test('keeps the three states apart within one batch', () async {
    await repository.cachePhotos('cached', [
      _photo('https://inat/a.jpg'),
    ], taxonId: 7);
    await repository.cachePhotos('looked-up-empty', [], taxonId: 8);

    final cached = await repository.getCachedPhotosForSpecies({
      'cached',
      'looked-up-empty',
      'never-looked-up',
    });

    expect(cached['cached'], hasLength(1));
    expect(cached['looked-up-empty'], isEmpty);
    expect(cached.containsKey('never-looked-up'), isFalse);
  });

  test('re-caching replaces what the species had before', () async {
    await repository.cachePhotos('sp1', [
      _photo('https://inat/old.jpg'),
    ], taxonId: 7);
    await repository.cachePhotos('sp1', [
      _photo('https://inat/new.jpg'),
    ], taxonId: 7);

    final cached = await repository.getCachedPhotosForSpecies({'sp1'});

    expect(cached['sp1']!.map((picture) => picture.url), [
      'https://inat/new.jpg',
    ]);
  });

  test('every row carries the taxon the photos came from', () async {
    await repository.cachePhotos('sp1', [
      _photo('https://inat/a.jpg'),
      _photo('https://inat/b.jpg'),
    ], taxonId: 7);
    await repository.cachePhotos('found-empty', [], taxonId: 8);
    await repository.cachePhotos('not-found', [], taxonId: null);

    final rows = await database.query(
      INatPhotoCacheRepository.tableName,
      columns: ['species_id', 'inat_taxon_id'],
      orderBy: 'species_id, photo_url',
    );
    expect(
      rows.map((row) => '${row['species_id']}=${row['inat_taxon_id']}'),
      ['found-empty=8', 'not-found=null', 'sp1=7', 'sp1=7'],
    );
  });

  test('an empty request reads nothing', () async {
    expect(await repository.getCachedPhotosForSpecies({}), isEmpty);
  });
}
