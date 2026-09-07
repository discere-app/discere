import 'package:discere/enrichment/model/enrichment_capability.dart';
import 'package:discere/enrichment/model/enrichment_work_state.dart';
import 'package:discere/enrichment/pipeline/repository/deck_projection_builder.dart';
import 'package:flutter_test/flutter_test.dart';

/// One joined row as `loadDeckProjection`'s species query produces it: a
/// species, one of its capabilities, and the two consent flags that ride
/// along from `enrichment_species_work`.
Map<String, Object?> speciesRow(
  String speciesId, {
  EnrichmentCapability? capability,
  EnrichmentWorkState? state,
  int? nextAttemptAt,
  int? referenceDbVersion,
  bool wantsInatPhotos = true,
  bool wantsCommonNames = true,
}) => {
  'species_id': speciesId,
  'capability': capability?.wireName,
  'state': state?.wireName,
  'next_attempt_at': nextAttemptAt,
  'reference_db_version': referenceDbVersion,
  'wants_inat_photos': wantsInatPhotos ? 1 : 0,
  'wants_common_names': wantsCommonNames ? 1 : 0,
};

Map<String, Object?> taxonomyRow(
  EnrichmentWorkState state, {
  int? nextAttemptAt,
}) => {
  'work_key': 'genus:acropora',
  'common_names_state': state.wireName,
  'next_attempt_at': nextAttemptAt,
};

Map<String, Object?> unresolvedRow(
  EnrichmentWorkState state, {
  int? nextAttemptAt,
}) => {'state': state.wireName, 'next_attempt_at': nextAttemptAt};

DeckProjectionBuilder builder({
  List<Map<String, Object?>> species = const [],
  List<Map<String, Object?>> taxonomy = const [],
  List<Map<String, Object?>> unresolved = const [],
  int? currentReferenceDbVersion,
}) => DeckProjectionBuilder(
  speciesRows: species,
  taxonomyRows: taxonomy,
  unresolvedNameRows: unresolved,
  currentReferenceDbVersion: currentReferenceDbVersion,
);

void main() {
  group('image completeness', () {
    test('a species whose base succeeded is complete without an iNat row', () {
      // BaseWorker only seeds inatPrimary when base does *not* succeed, so
      // "no row" has to read as complete here, not as unfinished.
      final projection = builder(
        species: [
          speciesRow(
            'sp-a',
            capability: EnrichmentCapability.base,
            state: EnrichmentWorkState.done,
          ),
        ],
      ).build('deck-1');

      expect(projection.speciesCount, 1);
      expect(projection.imageCompleteSpeciesCount, 1);
      expect(projection.imageDoneSpeciesCount, 1);
    });

    test('base without a result waits for iNat while consent is given', () {
      final rows = [
        speciesRow(
          'sp-a',
          capability: EnrichmentCapability.base,
          state: EnrichmentWorkState.noResult,
        ),
        speciesRow(
          'sp-a',
          capability: EnrichmentCapability.inatPrimary,
          state: EnrichmentWorkState.pending,
        ),
      ];

      expect(builder(species: rows).build('d').imageCompleteSpeciesCount, 0);
    });

    test('...and is complete once that iNat attempt is terminal', () {
      final rows = [
        speciesRow(
          'sp-a',
          capability: EnrichmentCapability.base,
          state: EnrichmentWorkState.noResult,
        ),
        speciesRow(
          'sp-a',
          capability: EnrichmentCapability.inatPrimary,
          state: EnrichmentWorkState.noResult,
        ),
      ];

      final projection = builder(species: rows).build('d');
      expect(projection.imageCompleteSpeciesCount, 1);
      // Terminal is not the same as having an image.
      expect(projection.imageDoneSpeciesCount, 0);
    });

    test('without iNat consent it is complete even though base found '
        'nothing', () {
      // The species never gets an inatPrimary row at all. Counting it as
      // unfinished would leave the whole deck in loadingBase forever,
      // waiting on a request that will never be made.
      final projection = builder(
        species: [
          speciesRow(
            'sp-a',
            capability: EnrichmentCapability.base,
            state: EnrichmentWorkState.noResult,
            wantsInatPhotos: false,
          ),
        ],
      ).build('d');

      expect(projection.imageCompleteSpeciesCount, 1);
      expect(projection.wantsInatPhotosSpeciesCount, 0);
    });

    test('a permanent image failure is reported separately', () {
      final projection = builder(
        species: [
          speciesRow(
            'sp-a',
            capability: EnrichmentCapability.base,
            state: EnrichmentWorkState.permanentFailure,
          ),
        ],
      ).build('d');

      expect(projection.anyImagePermanentFailure, isTrue);
      expect(projection.anyPermanentFailure, isTrue);
    });
  });

  group('stale base results', () {
    Map<String, Object?> base(EnrichmentWorkState state, int? stampedVersion) =>
        speciesRow(
          'sp-a',
          capability: EnrichmentCapability.base,
          state: state,
          referenceDbVersion: stampedVersion,
        );

    test('an older stamp counts as stale', () {
      final projection = builder(
        species: [base(EnrichmentWorkState.done, 4)],
        currentReferenceDbVersion: 5,
      ).build('d');

      expect(projection.staleBaseSpeciesCount, 1);
    });

    test('no stamp at all counts as stale', () {
      final projection = builder(
        species: [base(EnrichmentWorkState.done, null)],
        currentReferenceDbVersion: 5,
      ).build('d');

      expect(projection.staleBaseSpeciesCount, 1);
    });

    test('the current stamp does not', () {
      final projection = builder(
        species: [base(EnrichmentWorkState.done, 5)],
        currentReferenceDbVersion: 5,
      ).build('d');

      expect(projection.staleBaseSpeciesCount, 0);
    });

    test('a permanent failure is left alone', () {
      // It already spent its retry budget; reclaiming it would just spend it
      // again on the same failure.
      final projection = builder(
        species: [base(EnrichmentWorkState.permanentFailure, null)],
        currentReferenceDbVersion: 5,
      ).build('d');

      expect(projection.staleBaseSpeciesCount, 0);
    });

    test('nothing is judged stale without a current version', () {
      final projection = builder(
        species: [base(EnrichmentWorkState.done, 1)],
      ).build('d');

      expect(projection.staleBaseSpeciesCount, 0);
    });
  });

  group('optional capabilities', () {
    test('an absent capability is not wanted rather than unfinished', () {
      final projection = builder(
        species: [
          speciesRow(
            'sp-a',
            capability: EnrichmentCapability.base,
            state: EnrichmentWorkState.done,
          ),
        ],
      ).build('d');

      expect(projection.speciesCommonNamesWantedCount, 0);
      expect(projection.speciesCommonNamesTerminalCount, 0);
      expect(projection.inatBackfillWantedCount, 0);
    });

    test('a present one counts as wanted, and terminal only when it is', () {
      final projection = builder(
        species: [
          speciesRow(
            'sp-a',
            capability: EnrichmentCapability.speciesCommonNames,
            state: EnrichmentWorkState.pending,
          ),
          speciesRow(
            'sp-b',
            capability: EnrichmentCapability.speciesCommonNames,
            state: EnrichmentWorkState.done,
          ),
        ],
      ).build('d');

      expect(projection.speciesCommonNamesWantedCount, 2);
      expect(projection.speciesCommonNamesTerminalCount, 1);
    });
  });

  group('pending work and the earliest retry', () {
    test('a running row makes the deck immediately pending', () {
      final projection = builder(
        species: [
          speciesRow(
            'sp-a',
            capability: EnrichmentCapability.base,
            state: EnrichmentWorkState.running,
          ),
        ],
      ).build('d');

      expect(projection.hasImmediatePendingWork, isTrue);
      expect(projection.earliestRetryAt, isNull);
    });

    test('the earliest retry wins across all three row sets', () {
      final projection = builder(
        species: [
          speciesRow(
            'sp-a',
            capability: EnrichmentCapability.base,
            state: EnrichmentWorkState.retryScheduled,
            nextAttemptAt: 3000,
          ),
        ],
        taxonomy: [
          taxonomyRow(EnrichmentWorkState.retryScheduled, nextAttemptAt: 1000),
        ],
        unresolved: [
          unresolvedRow(EnrichmentWorkState.retryScheduled, nextAttemptAt: 2000),
        ],
      ).build('d');

      expect(projection.hasImmediatePendingWork, isFalse);
      expect(
        projection.earliestRetryAt,
        DateTime.fromMillisecondsSinceEpoch(1000),
      );
    });

    test('a scheduled retry without a timestamp is ignored', () {
      final projection = builder(
        taxonomy: [taxonomyRow(EnrichmentWorkState.retryScheduled)],
      ).build('d');

      expect(projection.earliestRetryAt, isNull);
    });
  });

  group('unresolved names', () {
    test('a permanently failed name is not pending, but is a failure', () {
      final projection = builder(
        unresolved: [
          unresolvedRow(EnrichmentWorkState.permanentFailure),
          unresolvedRow(EnrichmentWorkState.pending),
        ],
      ).build('d');

      expect(projection.pendingUnresolvedNameCount, 1);
      expect(projection.anyPermanentFailure, isTrue);
    });
  });

  test('a species appears once however many capability rows it has', () {
    final projection = builder(
      species: [
        speciesRow(
          'sp-a',
          capability: EnrichmentCapability.base,
          state: EnrichmentWorkState.done,
        ),
        speciesRow(
          'sp-a',
          capability: EnrichmentCapability.speciesCommonNames,
          state: EnrichmentWorkState.done,
        ),
        speciesRow(
          'sp-a',
          capability: EnrichmentCapability.inatBackfill,
          state: EnrichmentWorkState.pending,
        ),
      ],
    ).build('deck-1');

    expect(projection.speciesCount, 1);
    expect(projection.deckId, 'deck-1');
  });

  test('a species with no capability rows at all still counts', () {
    // The membership join is a LEFT JOIN: a species that was just added to
    // the deck has a membership row before it has any capability rows.
    final projection = builder(species: [speciesRow('sp-a')]).build('d');

    expect(projection.speciesCount, 1);
    expect(projection.imageCompleteSpeciesCount, 0);
  });
}
