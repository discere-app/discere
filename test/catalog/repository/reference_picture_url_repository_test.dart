import 'dart:io';

import 'package:discere/catalog/repository/reference_picture_url_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Runs against the curated reference-DB fixture (see
/// etl/scripts/build_test_fixture.sh), so the query meets the real
/// `pictures` table rather than a hand-written copy of it.
void main() {
  const species259 = 'discere:species:259';
  const species278 = 'discere:species:278';
  const unusablePictureOf259 =
      'https://www.fishbase.se/images/species/Abbra_ue.jpg';

  late Database referenceDb;
  late ReferencePictureUrlRepository repository;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    referenceDb = await openDatabase(
      File('test/fixtures/discere_reference_test.db').absolute.path,
      readOnly: true,
    );
    repository = ReferencePictureUrlRepository(database: referenceDb);
  });

  tearDownAll(() => referenceDb.close());

  test('answers every picture URL of the given species, unusable ones '
      'included', () async {
    final urls = await repository.urlsOf({species259, species278});

    // 16 pictures of 259 and 10 of 278, of which only 2 each are usable.
    expect(urls, hasLength(26));
    expect(urls, contains(unusablePictureOf259));
  });

  test('leaves out the pictures of species not asked for', () async {
    final only278 = await repository.urlsOf({species278});

    expect(only278, hasLength(10));
    expect(only278, isNot(contains(unusablePictureOf259)));
  });

  test('finds the species beyond the first batch of ids', () async {
    final urls = await repository.urlsOf({
      for (var i = 0; i < 1000; i++) 'discere:species:missing-$i',
      species259,
    });

    expect(urls, hasLength(16));
  });
}
