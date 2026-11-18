import 'dart:io';

import 'package:discere/app/bootstrap/species_image_storage_step.dart';
import 'package:discere/catalog/service/watchlist_service.dart';
import 'package:discere/enrichment/media/service/species_image_storage_sweeper.dart';
import 'package:discere/enrichment/pipeline/service/inat_provenance_reconciler.dart';
import 'package:discere/shared/persistence/database_helper.dart';
import 'package:discere/shared/persistence/reference_id/reference_id_migration.dart';
import 'package:discere/shared/service/cached_image_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'bootstrap_harness.dart';

const _rescued = 'discere:species:rescued';
const _released = 'discere:species:released';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  late Directory supportDir;
  late File rescuedFile;
  late File releasedFile;

  /// A species with a cached iNat photo and its file on disk.
  Future<File> withPhoto(String speciesId) async {
    final url = 'https://static.inaturalist.org/photos/$speciesId/medium.jpg';
    await (await DatabaseHelper.userDb).insert('inat_photo_cache', {
      'species_id': speciesId,
      'photo_url': url,
      'fetched_at': 1,
      'inat_taxon_id': 5,
    });
    final file = File(
      await CachedImageStore().pathFor(
        url,
        storageDirectory: 'external_images',
      ),
    );
    await file.parent.create(recursive: true);
    await file.writeAsBytes([1]);
    return file;
  }

  Future<String?> fingerprint() async => (await SharedPreferences.getInstance())
      .getString(SpeciesImageStorageSweeper.prefKeyFingerprint);

  setUp(() async {
    supportDir = await Directory.systemTemp.createTemp('image_storage_step');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (call) async {
          return supportDir.path;
        });
    await seedDatabases(supportDir);
    SharedPreferences.setMockInitialValues({
      ...installedPreferences(version: 2),
      ReferenceIdMigration.prefKeyAppliedVersion: 2,
      INatProvenanceReconciler.prefKeyReconciledVersion: 2,
    });
    rescuedFile = await withPhoto(_rescued);
    releasedFile = await withPhoto(_released);
  });

  tearDown(() async {
    await DatabaseHelper.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    await supportDir.delete(recursive: true);
  });

  group('keeps the images of a species', () {
    Future<void> expectRescued() async {
      await sweepSpeciesImageStorage();

      expect(await rescuedFile.exists(), isTrue);
      expect(await releasedFile.exists(), isFalse);
      expect(await fingerprint(), isNotNull);
    }

    test('that is a card of a deck', () async {
      final userDb = await DatabaseHelper.userDb;
      await userDb.insert('decks', {'id': 'deck-1', 'name': 'Deck'});
      await userDb.insert('flashcard_stats', {
        'species_id': _rescued,
        'deck_id': 'deck-1',
      });

      await expectRescued();
    });

    test('that is a member of a deck being enriched', () async {
      await (await DatabaseHelper.userDb).insert(
        'enrichment_species_deck_membership',
        {'species_id': _rescued, 'deck_id': 'deck-1'},
      );

      await expectRescued();
    });

    test('on the watchlist', () async {
      await (await SharedPreferences.getInstance()).setStringList(
        WatchlistService.watchlistKey,
        [_rescued],
      );

      await expectRescued();
    });

    test('in a comparison list', () async {
      final userDb = await DatabaseHelper.userDb;
      await userDb.insert('comparison_lists', {
        'id': 'list-1',
        'name': 'List',
        'created_at': 1,
      });
      await userDb.insert('comparison_list_species', {
        'list_id': 'list-1',
        'species_id': _rescued,
        'position': 0,
      });

      await expectRescued();
    });
  });

  test('waits until the iNat data is reconciled with the installed '
      'database', () async {
    await (await SharedPreferences.getInstance()).setInt(
      INatProvenanceReconciler.prefKeyReconciledVersion,
      1,
    );

    await sweepSpeciesImageStorage();

    expect(await releasedFile.exists(), isTrue);
    expect(await fingerprint(), isNull);
  });

  test('a failure lets the start go on and leaves the sweep to the next '
      'start', () async {
    await (await DatabaseHelper.userDb).execute('DROP TABLE inat_photo_cache');

    await sweepSpeciesImageStorage();

    expect(await rescuedFile.exists(), isTrue);
    expect(await releasedFile.exists(), isTrue);
    expect(await fingerprint(), isNull);
  });
}
