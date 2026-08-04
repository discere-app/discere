import 'package:discere/catalog/model/picture.dart';
import 'package:discere/diagnostics/service/local_diagnostics.dart';
import 'package:discere/enrichment/pipeline/model/enrichment_work_plan.dart';
import 'package:discere/enrichment/pipeline/model/import_enrichment_summary.dart';
import 'package:discere/enrichment/pipeline/repository/enrichment_work_repository.dart';
import 'package:discere/enrichment/pipeline/service/inat_worker.dart';
import 'package:discere/enrichment/ports/enrichment_job_ports.dart';
import 'package:discere/enrichment/queue/model/enrichment_job.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:sqflite/sqflite.dart';

import '../../../mocks.mocks.dart';
import '../../../support/in_memory_user_database.dart';

class _FakeNameResolutionPort implements ScientificNameResolutionPort {
  final Map<String, String> resolutions;
  const _FakeNameResolutionPort(this.resolutions);

  @override
  Future<Map<String, String>> resolveNames(List<String> names) async {
    return {
      for (final name in names)
        if (resolutions.containsKey(name)) name: resolutions[name]!,
    };
  }
}

class _FakeDeckSpeciesMutationPort implements DeckSpeciesMutationPort {
  final List<(String, Set<String>)> additions = [];

  @override
  Future<void> addSpeciesToDeck(String deckId, Set<String> speciesIds) async {
    additions.add((deckId, speciesIds));
  }
}

class _FakeUnresolvedNamesObserver implements UnresolvedNamesObserverPort {
  final List<(String, List<String>)> notifications = [];

  @override
  void onNamesUnresolved(String deckId, List<String> stillUnresolved) {
    notifications.add((deckId, stillUnresolved));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database database;
  late EnrichmentWorkRepository workRepository;
  late MockINatPhotoEnrichmentService photoEnrichmentService;
  late MockSpeciesCommonNameEnrichmentService commonNameEnrichmentService;
  late MockTaxonomyCommonNameEnrichmentService taxonomyService;
  late MockINatPhotoCacheRepository photoCacheRepository;
  late _FakeDeckSpeciesMutationPort deckSpeciesMutationPort;
  late _FakeUnresolvedNamesObserver unresolvedNamesObserver;

  setUp(() async {
    database = await openInMemoryUserDatabase();
    workRepository = EnrichmentWorkRepository(database);
    photoEnrichmentService = MockINatPhotoEnrichmentService();
    commonNameEnrichmentService = MockSpeciesCommonNameEnrichmentService();
    taxonomyService = MockTaxonomyCommonNameEnrichmentService();
    photoCacheRepository = MockINatPhotoCacheRepository();
    deckSpeciesMutationPort = _FakeDeckSpeciesMutationPort();
    unresolvedNamesObserver = _FakeUnresolvedNamesObserver();

    when(
      taxonomyService.buildTaxonomyWorkPlanForSpecies(any),
    ).thenAnswer((_) async => const <TaxonomyWorkPlanItem>[]);
  });

  tearDown(() async {
    await database.close();
  });

  INatWorker buildWorker({ScientificNameResolutionPort? nameResolutionPort}) {
    return INatWorker(
      photoEnrichmentService,
      commonNameEnrichmentService,
      taxonomyService,
      workRepository,
      photoCacheRepository,
      diagnostics: LocalDiagnostics(enabled: false),
      nameResolutionPort: nameResolutionPort,
      deckSpeciesMutationPort: deckSpeciesMutationPort,
      unresolvedNamesObserver: unresolvedNamesObserver,
    );
  }

  Future<void> seedSpecies(String speciesId, {bool wantsCommonNames = false}) {
    return workRepository.assignSpeciesOwners(
      speciesIdsByDeckId: {
        'deck-1': {speciesId},
      },
      prioritizedDeckIds: ['deck-1'],
      includeCommonNamesByDeckId: {'deck-1': wantsCommonNames},
    );
  }

  Future<Map<String, Object?>> loadCapability(
    String speciesId,
    String capability,
  ) async {
    final rows = await database.query(
      EnrichmentWorkRepository.capabilityStateTable,
      where: 'species_id = ? AND capability = ?',
      whereArgs: [speciesId, capability],
    );
    return rows.isEmpty ? const {} : rows.single;
  }

  /// `runUntilIdle` drains the whole queue, including items reactively
  /// seeded by processing an earlier one — this stops it after exactly one
  /// claimed item, for tests that want to inspect a single handler's direct
  /// effects (e.g. "did it seed a follow-up row") without also exercising
  /// whatever gets seeded next.
  bool Function() stopAfterOneItem() {
    var callCount = 0;
    return () => callCount++ > 0;
  }

  test('a successful primary photo fetch marks inatPrimary done and seeds '
      'backfill', () async {
    await seedSpecies('sp-a');
    await workRepository.seedCapability(
      'sp-a',
      EnrichmentStage.inatPrimary,
      priorityTier: 10,
    );
    when(
      photoEnrichmentService.fetchINatPhotosForSpecies(
        any,
        primaryOnly: anyNamed('primaryOnly'),
        onSpeciesCompleted: anyNamed('onSpeciesCompleted'),
      ),
    ).thenAnswer((invocation) async {
      final onCompleted =
          invocation.namedArguments[#onSpeciesCompleted]
              as void Function(String)?;
      onCompleted?.call('sp-a');
      return ImportEnrichmentSummary.empty;
    });
    when(photoCacheRepository.getCachedPhotos('sp-a')).thenAnswer(
      (_) async => const [
        Picture(id: 'p1', species: 'sp-a', origin: 'iNaturalist', isUsable: 1),
      ],
    );

    final processedAny = await buildWorker().runUntilIdle(
      shouldStop: stopAfterOneItem(),
    );

    expect(processedAny, isTrue);
    expect((await loadCapability('sp-a', 'inatPrimary'))['state'], 'done');
    final backfill = await loadCapability('sp-a', 'inatBackfill');
    expect(backfill['state'], 'pending');
    expect(backfill['priority_tier'], 40);
  });

  test('a primary photo fetch that finds nothing marks inatPrimary noResult '
      'but still seeds backfill', () async {
    await seedSpecies('sp-a');
    await workRepository.seedCapability(
      'sp-a',
      EnrichmentStage.inatPrimary,
      priorityTier: 10,
    );
    when(
      photoEnrichmentService.fetchINatPhotosForSpecies(
        any,
        primaryOnly: anyNamed('primaryOnly'),
        onSpeciesCompleted: anyNamed('onSpeciesCompleted'),
      ),
    ).thenAnswer((invocation) async {
      final onCompleted =
          invocation.namedArguments[#onSpeciesCompleted]
              as void Function(String)?;
      onCompleted?.call('sp-a');
      return ImportEnrichmentSummary.empty;
    });
    when(
      photoCacheRepository.getCachedPhotos('sp-a'),
    ).thenAnswer((_) async => const []);

    await buildWorker().runUntilIdle(shouldStop: stopAfterOneItem());

    expect((await loadCapability('sp-a', 'inatPrimary'))['state'], 'noResult');
    expect((await loadCapability('sp-a', 'inatBackfill'))['state'], 'pending');
  });

  test('a primary photo fetch that never completes retries instead of '
      'declaring a terminal outcome', () async {
    await seedSpecies('sp-a');
    await workRepository.seedCapability(
      'sp-a',
      EnrichmentStage.inatPrimary,
      priorityTier: 10,
    );
    when(
      photoEnrichmentService.fetchINatPhotosForSpecies(
        any,
        primaryOnly: anyNamed('primaryOnly'),
        onSpeciesCompleted: anyNamed('onSpeciesCompleted'),
      ),
    ).thenAnswer((_) async => ImportEnrichmentSummary.empty);

    await buildWorker().runUntilIdle(shouldStop: () => false);

    final capability = await loadCapability('sp-a', 'inatPrimary');
    expect(capability['state'], 'retryScheduled');
    expect(capability['attempt_count'], 1);
    verifyNever(photoCacheRepository.getCachedPhotos(any));
  });

  test('a species common-name fetch marks the capability done regardless of '
      'whether names were actually found', () async {
    await seedSpecies('sp-a', wantsCommonNames: true);
    when(
      commonNameEnrichmentService.fetchSpeciesCommonNamesForSpecies(
        any,
        onSpeciesCompleted: anyNamed('onSpeciesCompleted'),
      ),
    ).thenAnswer((invocation) async {
      final onCompleted =
          invocation.namedArguments[#onSpeciesCompleted]
              as void Function(String)?;
      onCompleted?.call('sp-a');
      return ImportEnrichmentSummary.empty;
    });

    await buildWorker().runUntilIdle(shouldStop: () => false);

    expect(
      (await loadCapability('sp-a', 'speciesCommonNames'))['state'],
      'done',
    );
  });

  test('a backfill fetch that completes marks inatBackfill done', () async {
    await seedSpecies('sp-a');
    await workRepository.seedCapability(
      'sp-a',
      EnrichmentStage.inatBackfill,
      priorityTier: 40,
    );
    when(
      photoEnrichmentService.backfillINatPhotosForSpecies(
        any,
        onSpeciesCompleted: anyNamed('onSpeciesCompleted'),
      ),
    ).thenAnswer((invocation) async {
      final onCompleted =
          invocation.namedArguments[#onSpeciesCompleted]
              as void Function(String)?;
      onCompleted?.call('sp-a');
      return ImportEnrichmentSummary.empty;
    });

    await buildWorker().runUntilIdle(shouldStop: () => false);

    expect((await loadCapability('sp-a', 'inatBackfill'))['state'], 'done');
  });

  test(
    'a taxonomy common-name fetch that completes marks the work item done',
    () async {
      // Membership + junction so the claim guard (a taxon is claimable only
      // while one of its species still has a live deck membership) passes.
      await database.insert(EnrichmentWorkRepository.deckMembershipTable, {
        'species_id': 'sp-a',
        'deck_id': 'deck-1',
      });
      await database.insert(EnrichmentWorkRepository.taxonomyWorkTable, {
        'work_key': 'genus:acropora',
        'runtime_entity_key': 'genus:acropora',
        'common_names_state': 'pending',
        'attempt_count': 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });
      await database.insert(EnrichmentWorkRepository.taxonomyWorkSpeciesTable, {
        'work_key': 'genus:acropora',
        'species_id': 'sp-a',
      });
      when(
        taxonomyService.fetchINatTaxonomyCommonNamesForEntityKeys(
          any,
          entityKeys: anyNamed('entityKeys'),
          onEntityCompleted: anyNamed('onEntityCompleted'),
        ),
      ).thenAnswer((invocation) async {
        final onCompleted =
            invocation.namedArguments[#onEntityCompleted]
                as void Function(String)?;
        onCompleted?.call('genus:acropora');
        return ImportEnrichmentSummary.empty;
      });

      await buildWorker().runUntilIdle(shouldStop: () => false);

      final rows = await database.query(
        EnrichmentWorkRepository.taxonomyWorkTable,
        where: 'work_key = ?',
        whereArgs: ['genus:acropora'],
      );
      expect(rows.single['common_names_state'], 'done');
    },
  );

  test('a resolved name registers the species for the deck with the consent '
      'it was submitted under, and removes the unresolved-name row', () async {
    await database.insert(EnrichmentWorkRepository.unresolvedNamesTable, {
      'deck_id': 'deck-1',
      'name': 'Unknownus fishus',
      'state': 'pending',
      'wants_inat_photos': 1,
      'wants_common_names': 0,
      'attempt_count': 0,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    });
    final worker = buildWorker(
      nameResolutionPort: const _FakeNameResolutionPort({
        'Unknownus fishus': 'sp-resolved',
      }),
    );

    final processedAny = await worker.runUntilIdle(shouldStop: () => false);

    expect(processedAny, isTrue);
    // Compared field-by-field rather than as a whole record: records compare
    // their fields with plain `==`, and Set/List don't have value equality
    // under `==` (only under matcher's `equals()`), so comparing a whole
    // (String, Set<String>) tuple directly can spuriously fail even when the
    // contents match.
    expect(deckSpeciesMutationPort.additions, hasLength(1));
    final (additionDeckId, additionSpeciesIds) =
        deckSpeciesMutationPort.additions.single;
    expect(additionDeckId, 'deck-1');
    expect(additionSpeciesIds, {'sp-resolved'});
    final speciesWorkRows = await database.query(
      EnrichmentWorkRepository.speciesWorkTable,
      where: 'species_id = ?',
      whereArgs: ['sp-resolved'],
    );
    expect(speciesWorkRows.single['wants_inat_photos'], 1);
    expect(speciesWorkRows.single['wants_common_names'], 0);
    expect((await loadCapability('sp-resolved', 'base'))['state'], 'pending');
    expect(await loadCapability('sp-resolved', 'speciesCommonNames'), isEmpty);
    final unresolvedRows = await database.query(
      EnrichmentWorkRepository.unresolvedNamesTable,
    );
    expect(unresolvedRows, isEmpty);
  });

  test('a name that never resolves gives up after the attempt cap and notifies '
      'the observer', () async {
    await database.insert(EnrichmentWorkRepository.unresolvedNamesTable, {
      'deck_id': 'deck-1',
      'name': 'Ghostus fishus',
      'state': 'pending',
      'wants_inat_photos': 1,
      'wants_common_names': 1,
      'attempt_count': 0,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    });
    final worker = buildWorker(
      nameResolutionPort: const _FakeNameResolutionPort({}),
    );

    for (var attempt = 0; attempt < 5; attempt++) {
      await worker.runUntilIdle(shouldStop: () => false);
      await database.update(
        EnrichmentWorkRepository.unresolvedNamesTable,
        {'next_attempt_at': null},
        where: 'deck_id = ? AND name = ?',
        whereArgs: ['deck-1', 'Ghostus fishus'],
      );
    }

    final rows = await database.query(
      EnrichmentWorkRepository.unresolvedNamesTable,
    );
    expect(rows.single['state'], 'permanentFailure');
    expect(rows.single['attempt_count'], 5);
    expect(unresolvedNamesObserver.notifications, hasLength(1));
    final (notifiedDeckId, notifiedNames) =
        unresolvedNamesObserver.notifications.single;
    expect(notifiedDeckId, 'deck-1');
    expect(notifiedNames, ['Ghostus fishus']);
  });

  test('without a name resolution port wired, an unresolved name is simply '
      'dropped instead of retried forever', () async {
    await database.insert(EnrichmentWorkRepository.unresolvedNamesTable, {
      'deck_id': 'deck-1',
      'name': 'Orphan fishus',
      'state': 'pending',
      'wants_inat_photos': 1,
      'wants_common_names': 1,
      'attempt_count': 0,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    });

    await buildWorker(
      nameResolutionPort: null,
    ).runUntilIdle(shouldStop: () => false);

    final rows = await database.query(
      EnrichmentWorkRepository.unresolvedNamesTable,
    );
    expect(rows, isEmpty);
  });

  test('runUntilIdle returns false when there is no claimable work', () async {
    final processedAny = await buildWorker().runUntilIdle(
      shouldStop: () => false,
    );
    expect(processedAny, isFalse);
  });

  test('runUntilIdle stops early once shouldStop returns true', () async {
    await seedSpecies('sp-a', wantsCommonNames: true);

    final processedAny = await buildWorker().runUntilIdle(
      shouldStop: () => true,
    );

    expect(processedAny, isFalse);
    verifyNever(
      commonNameEnrichmentService.fetchSpeciesCommonNamesForSpecies(
        any,
        onSpeciesCompleted: anyNamed('onSpeciesCompleted'),
      ),
    );
  });

  test('drains multiple items in priority order across species and taxonomy '
      'sources within one runUntilIdle call', () async {
    await seedSpecies('sp-a', wantsCommonNames: true);
    // sp-b only ever gets this one reactive capability seeded (mirrors how
    // BaseWorker's fallback seeding works for a species with no reference
    // image) — but seedCapability is consent-gated for inatPrimary/
    // inatBackfill, so a consenting speciesWorkTable row still needs to
    // exist first, same as it always does in production by the time any
    // worker reactively seeds iNat work for a species.
    await workRepository.assignSpeciesOwners(
      speciesIdsByDeckId: {
        'deck-2': {'sp-b'},
      },
      prioritizedDeckIds: ['deck-2'],
      includeInatPhotosByDeckId: {'deck-2': true},
    );
    await workRepository.seedCapability(
      'sp-b',
      EnrichmentStage.inatPrimary,
      priorityTier: 10,
    );
    when(
      photoEnrichmentService.fetchINatPhotosForSpecies(
        any,
        primaryOnly: anyNamed('primaryOnly'),
        onSpeciesCompleted: anyNamed('onSpeciesCompleted'),
      ),
    ).thenAnswer((invocation) async {
      final onCompleted =
          invocation.namedArguments[#onSpeciesCompleted]
              as void Function(String)?;
      onCompleted?.call('sp-b');
      return ImportEnrichmentSummary.empty;
    });
    when(
      photoCacheRepository.getCachedPhotos('sp-b'),
    ).thenAnswer((_) async => const []);
    when(
      commonNameEnrichmentService.fetchSpeciesCommonNamesForSpecies(
        any,
        onSpeciesCompleted: anyNamed('onSpeciesCompleted'),
      ),
    ).thenAnswer((invocation) async {
      final onCompleted =
          invocation.namedArguments[#onSpeciesCompleted]
              as void Function(String)?;
      onCompleted?.call('sp-a');
      return ImportEnrichmentSummary.empty;
    });

    final processedAny = await buildWorker().runUntilIdle(
      shouldStop: () => false,
    );

    expect(processedAny, isTrue);
    // sp-b's inatPrimary (tier 10) must be processed before sp-a's
    // speciesCommonNames (tier 20).
    expect((await loadCapability('sp-b', 'inatPrimary'))['state'], 'noResult');
    expect(
      (await loadCapability('sp-a', 'speciesCommonNames'))['state'],
      'done',
    );
  });
}
