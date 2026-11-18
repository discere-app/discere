import 'package:discere/enrichment/media/repository/species_image_retention_repository.dart';
import 'package:discere/enrichment/model/enrichment_capability.dart';
import 'package:discere/enrichment/model/enrichment_work_state.dart';
import 'package:discere/enrichment/pipeline/model/inat_work_item.dart';
import 'package:discere/enrichment/pipeline/repository/enrichment_ownership_repository.dart';
import 'package:discere/enrichment/pipeline/repository/enrichment_work_claim_repository.dart';
import 'package:discere/enrichment/pipeline/repository/enrichment_work_outcome_repository.dart';
import 'package:discere/enrichment/pipeline/repository/inat_photo_cache_repository.dart';
import 'package:discere/external/inaturalist/models/inat_photo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import '../../../support/in_memory_user_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database database;
  late SpeciesImageRetentionRepository repository;
  late EnrichmentOwnershipRepository ownership;
  late EnrichmentWorkOutcomeRepository outcomes;
  late EnrichmentWorkClaimRepository claims;

  Future<void> cachePhotos(String speciesId) =>
      INatPhotoCacheRepository(database: database).cachePhotos(speciesId, [
        INatPhoto(
          url: 'https://static.inaturalist.org/photos/$speciesId/square.jpg',
          attribution: 'someone',
          licenseCode: 'cc-by',
        ),
      ], taxonId: 7);

  /// A species enriched in [deckId] with iNat photos, which then left it:
  /// everything done, no deck left.
  Future<void> enrichedAndLeft(String speciesId, String deckId) async {
    await ownership.assignSpeciesOwners(
      speciesIdsByDeckId: {
        deckId: {speciesId},
      },
      prioritizedDeckIds: [deckId],
      includeInatPhotosByDeckId: {deckId: true},
      includeCommonNamesByDeckId: {deckId: true},
    );
    for (final capability in [
      EnrichmentCapability.inatPrimary,
      EnrichmentCapability.inatBackfill,
    ]) {
      await outcomes.seedCapability(speciesId, capability, priorityTier: 10);
    }
    for (final capability in EnrichmentCapability.values) {
      await outcomes.markCapabilityTerminal(
        speciesId,
        capability,
        EnrichmentWorkState.done,
        referenceDbVersion: 2,
      );
    }
    await cachePhotos(speciesId);
    await ownership.releaseDeck(deckId);
  }

  setUp(() async {
    database = await openInMemoryUserDatabase();
    repository = SpeciesImageRetentionRepository(database: database);
    ownership = EnrichmentOwnershipRepository(database);
    outcomes = EnrichmentWorkOutcomeRepository(database);
    claims = EnrichmentWorkClaimRepository(database);
  });

  tearDown(() => database.close());

  test('speciesWithImageData answers the species with cached photos or an '
      'image work row, but not one with only a names row', () async {
    await cachePhotos('sp-photos');
    await outcomes.seedCapability(
      'sp-base',
      EnrichmentCapability.base,
      priorityTier: 0,
    );
    await outcomes.seedCapability(
      'sp-names',
      EnrichmentCapability.speciesCommonNames,
      priorityTier: 20,
    );

    expect(await repository.speciesWithImageData(), {'sp-photos', 'sp-base'});
  });

  group('a species let go and put into a deck again', () {
    setUp(() async {
      await enrichedAndLeft('sp-a', 'deck-old');
      await repository.release({'sp-a'});
    });

    test('has its reference images fetched again', () async {
      await ownership.assignSpeciesOwners(
        speciesIdsByDeckId: {
          'deck-new': {'sp-a'},
        },
        prioritizedDeckIds: ['deck-new'],
      );

      expect(await claims.claimBaseWorkBatch(limit: 10), ['sp-a']);
    });

    test('has its iNat photos fetched again where the new deck '
        'consents', () async {
      await ownership.assignSpeciesOwners(
        speciesIdsByDeckId: {
          'deck-new': {'sp-a'},
        },
        prioritizedDeckIds: ['deck-new'],
        includeInatPhotosByDeckId: {'deck-new': true},
      );
      await claims.claimBaseWorkBatch(limit: 10);
      // What BaseWorker seeds once the reference image is saved.
      await outcomes.markCapabilityTerminal(
        'sp-a',
        EnrichmentCapability.base,
        EnrichmentWorkState.done,
      );
      await outcomes.seedCapability(
        'sp-a',
        EnrichmentCapability.inatBackfill,
        priorityTier: 40,
      );

      final item = await claims.claimNextINatWorkItem();
      expect(item?.kind, INatWorkItemKind.inatBackfill);
      expect(item?.speciesId, 'sp-a');
    });

    test('has no iNat photos fetched where the new deck does not '
        'consent', () async {
      await ownership.assignSpeciesOwners(
        speciesIdsByDeckId: {
          'deck-new': {'sp-a'},
        },
        prioritizedDeckIds: ['deck-new'],
        includeInatPhotosByDeckId: {'deck-new': false},
      );

      expect(await claims.claimNextINatWorkItem(), isNull);
    });
  });
}
