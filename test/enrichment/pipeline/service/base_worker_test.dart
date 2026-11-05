import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/picture.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/enrichment/pipeline/model/base_image_download_result.dart';
import 'package:discere/enrichment/pipeline/model/base_image_fallback_reason.dart';
import 'package:discere/enrichment/pipeline/repository/enrichment_ownership_repository.dart';
import 'package:discere/enrichment/pipeline/repository/enrichment_work_claim_repository.dart';
import 'package:discere/enrichment/pipeline/repository/enrichment_work_outcome_repository.dart';
import 'package:discere/enrichment/pipeline/repository/enrichment_work_tables.dart';
import 'package:discere/enrichment/pipeline/service/base_worker.dart';
import 'package:discere/shared/persistence/reference_database_provisioner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../../../mocks.mocks.dart';
import '../../../support/in_memory_user_database.dart';
import '../../../support/persisted_warnings.dart';

Species _species(String id, {bool withReferencePicture = true}) {
  return Species(
    id,
    id,
    'mockSource',
    'mockName',
    const {},
    Classification(
      '',
      const {},
      null,
      '',
      const {},
      '',
      const {},
      '',
      const {},
      null,
    ),
    withReferencePicture
        ? [
            Picture(
              id: '$id-pic',
              species: id,
              origin: 'fishbase',
              isUsable: 1,
              url: 'https://example.com/$id.jpg',
            ),
          ]
        : const [],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database database;
  late EnrichmentOwnershipRepository ownershipRepository;
  late EnrichmentWorkClaimRepository claims;
  late EnrichmentWorkOutcomeRepository outcomes;
  late MockBaseImageEnrichmentService baseImageEnrichmentService;
  late MockSpeciesRepository speciesRepository;
  late BaseWorker worker;

  setUp(() async {
    provideDummy<BaseImageDownloadResult>(const BaseImageSaved());
    SharedPreferences.setMockInitialValues({});
    database = await openInMemoryUserDatabase();
    ownershipRepository = EnrichmentOwnershipRepository(database);
    claims = EnrichmentWorkClaimRepository(database);
    outcomes = EnrichmentWorkOutcomeRepository(database);
    baseImageEnrichmentService = MockBaseImageEnrichmentService();
    speciesRepository = MockSpeciesRepository();
    worker = BaseWorker(
      baseImageEnrichmentService,
      claims,
      outcomes,
      speciesRepository,
    );
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> seedSpecies(String speciesId) {
    return ownershipRepository.assignSpeciesOwners(
      speciesIdsByDeckId: {
        'deck-1': {speciesId},
      },
      prioritizedDeckIds: ['deck-1'],
    );
  }

  Future<Map<String, Object?>> loadCapability(
    String speciesId,
    String capability,
  ) async {
    final rows = await database.query(
      EnrichmentWorkTables.capabilityState,
      where: 'species_id = ? AND capability = ?',
      whereArgs: [speciesId, capability],
    );
    return rows.isEmpty ? const {} : rows.single;
  }

  test(
    'a species with no reference picture at all falls back to iNat '
    'immediately, without ever calling downloadReferenceImages',
    () async {
      await seedSpecies('sp-no-pic');
      when(speciesRepository.getSpecies(any)).thenAnswer(
        (_) async => {_species('sp-no-pic', withReferencePicture: false)},
      );

      final processedAny = await worker.runUntilIdle(shouldStop: () => false);

      expect(processedAny, isTrue);
      verifyNever(baseImageEnrichmentService.downloadReferenceImages(any));

      final base = await loadCapability('sp-no-pic', 'base');
      expect(base['state'], 'noResult');

      final inatPrimary = await loadCapability('sp-no-pic', 'inatPrimary');
      expect(inatPrimary['state'], 'pending');
      expect(inatPrimary['priority_tier'], 10);

      final inatBackfill = await loadCapability('sp-no-pic', 'inatBackfill');
      expect(inatBackfill['state'], 'pending');
      expect(inatBackfill['priority_tier'], 40);
    },
  );

  test('a successful download marks base done and seeds a low-priority '
      'backfill item, without touching inatPrimary', () async {
    await seedSpecies('sp-a');
    when(
      speciesRepository.getSpecies(any),
    ).thenAnswer((_) async => {_species('sp-a')});
    when(
      baseImageEnrichmentService.downloadReferenceImages(any),
    ).thenAnswer((_) async => const BaseImageSaved());

    await worker.runUntilIdle(shouldStop: () => false);

    final base = await loadCapability('sp-a', 'base');
    expect(base['state'], 'done');

    final inatBackfill = await loadCapability('sp-a', 'inatBackfill');
    expect(inatBackfill['state'], 'pending');
    expect(inatBackfill['priority_tier'], 40);

    final inatPrimary = await loadCapability('sp-a', 'inatPrimary');
    expect(inatPrimary, isEmpty);
  });

  test('stamps the currently-installed reference-DB version on a successful '
      'download', () async {
    SharedPreferences.setMockInitialValues({
      ReferenceDatabaseProvisioner.prefKeyVersion: 7,
    });
    await seedSpecies('sp-a');
    when(
      speciesRepository.getSpecies(any),
    ).thenAnswer((_) async => {_species('sp-a')});
    when(
      baseImageEnrichmentService.downloadReferenceImages(any),
    ).thenAnswer((_) async => const BaseImageSaved());

    await worker.runUntilIdle(shouldStop: () => false);

    final base = await loadCapability('sp-a', 'base');
    expect(base['state'], 'done');
    expect(base['reference_db_version'], 7);
  });

  test('stamps the currently-installed reference-DB version on a species '
      'with no reference picture (noResult)', () async {
    SharedPreferences.setMockInitialValues({
      ReferenceDatabaseProvisioner.prefKeyVersion: 7,
    });
    await seedSpecies('sp-no-pic');
    when(speciesRepository.getSpecies(any)).thenAnswer(
      (_) async => {_species('sp-no-pic', withReferencePicture: false)},
    );

    await worker.runUntilIdle(shouldStop: () => false);

    final base = await loadCapability('sp-no-pic', 'base');
    expect(base['state'], 'noResult');
    expect(base['reference_db_version'], 7);
  });

  test('leaves reference_db_version null when no reference DB has ever been '
      'installed', () async {
    await seedSpecies('sp-a');
    when(
      speciesRepository.getSpecies(any),
    ).thenAnswer((_) async => {_species('sp-a')});
    when(
      baseImageEnrichmentService.downloadReferenceImages(any),
    ).thenAnswer((_) async => const BaseImageSaved());

    await worker.runUntilIdle(shouldStop: () => false);

    final base = await loadCapability('sp-a', 'base');
    expect(base['state'], 'done');
    expect(base['reference_db_version'], isNull);
  });

  /// Runs the worker [times] times, each time against a failure for
  /// [reason] at [host], making the retry due at once in between rather than
  /// waiting out the real backoff.
  Future<void> failAttempts(
    int times, {
    BaseImageFallbackReason reason = BaseImageFallbackReason.hostUnavailable,
    String? host = 'www.fishbase.se',
  }) async {
    when(
      baseImageEnrichmentService.downloadReferenceImages(any),
    ).thenAnswer((_) async => BaseImageFailed(reason, host: host));
    for (var attempt = 0; attempt < times; attempt++) {
      await database.update(
        EnrichmentWorkTables.capabilityState,
        {'next_attempt_at': null},
        where: "species_id = ? AND capability = 'base'",
        whereArgs: ['sp-a'],
      );
      await worker.runUntilIdle(shouldStop: () => false);
    }
  }

  /// How far [row]'s retry lies from now.
  Duration retryDelayOf(Map<String, Object?> row) =>
      DateTime.fromMillisecondsSinceEpoch(
        row['next_attempt_at'] as int,
      ).difference(DateTime.now());

  group('a host problem', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({
        ReferenceDatabaseProvisioner.prefKeyVersion: 7,
      });
      await seedSpecies('sp-a');
      when(
        speciesRepository.getSpecies(any),
      ).thenAnswer((_) async => {_species('sp-a')});
    });

    test('is retried shortly after the first failure, without falling back '
        'to iNat yet', () async {
      await failAttempts(1);

      final base = await loadCapability('sp-a', 'base');
      expect(base['state'], 'retryScheduled');
      expect(base['attempt_count'], 1);
      expect(
        retryDelayOf(base),
        lessThanOrEqualTo(const Duration(seconds: 15)),
      );
      expect(base['fallback_reason'], isNull);
      expect(await loadCapability('sp-a', 'inatPrimary'), isEmpty);
    });

    test('falls back to iNat after the second failure, marks the species '
        'and retries the reference image a day later', () async {
      final before = DateTime.now().millisecondsSinceEpoch;

      await failAttempts(2);

      final inatPrimary = await loadCapability('sp-a', 'inatPrimary');
      expect(inatPrimary['state'], 'pending');
      expect(inatPrimary['priority_tier'], 10);
      final inatBackfill = await loadCapability('sp-a', 'inatBackfill');
      expect(inatBackfill['state'], 'pending');
      expect(inatBackfill['priority_tier'], 40);
      final base = await loadCapability('sp-a', 'base');
      expect(base['state'], 'retryScheduled');
      expect(base['attempt_count'], 2);
      expect(
        retryDelayOf(base),
        greaterThan(const Duration(hours: 23, minutes: 59)),
      );
      expect(base['fallback_reason'], 'hostUnavailable');
      expect(base['fallback_host'], 'www.fishbase.se');
      expect(base['fallback_at'], greaterThanOrEqualTo(before));
    });

    test('gives up after the fifth failure, stamping the reference-DB '
        'version and keeping the marking of the fallback', () async {
      await failAttempts(2, host: 'www.fishbase.se');
      await failAttempts(3, host: 'fishbase.de');

      final base = await loadCapability('sp-a', 'base');
      expect(base['state'], 'permanentFailure');
      expect(base['attempt_count'], 5);
      expect(base['reference_db_version'], 7);
      expect(base['fallback_host'], 'www.fishbase.se');
    });
  });

  test('a missing image is given up on at once, falling back to iNat and '
      'marking the species', () async {
    SharedPreferences.setMockInitialValues({
      ReferenceDatabaseProvisioner.prefKeyVersion: 7,
    });
    await seedSpecies('sp-a');
    when(
      speciesRepository.getSpecies(any),
    ).thenAnswer((_) async => {_species('sp-a')});

    await failAttempts(1, reason: BaseImageFallbackReason.imageMissing);

    final base = await loadCapability('sp-a', 'base');
    expect(base['state'], 'permanentFailure');
    expect(base['attempt_count'], 1);
    expect(base['reference_db_version'], 7);
    expect(base['fallback_reason'], 'imageMissing');
    expect(base['fallback_host'], 'www.fishbase.se');
    expect((await loadCapability('sp-a', 'inatPrimary'))['state'], 'pending');
  });

  test('an exception from downloadReferenceImages is booked as a failed '
      'attempt and retried like a host problem, not thrown', () async {
    await seedSpecies('sp-a');
    when(
      speciesRepository.getSpecies(any),
    ).thenAnswer((_) async => {_species('sp-a')});
    when(
      baseImageEnrichmentService.downloadReferenceImages(any),
    ).thenThrow(StateError('boom'));

    final processedAny = await worker.runUntilIdle(shouldStop: () => false);

    expect(processedAny, isTrue);
    final base = await loadCapability('sp-a', 'base');
    expect(base['state'], 'retryScheduled');
    expect(base['attempt_count'], 1);
    expect(base['last_error'], 'Bad state: boom');
    expect(await loadCapability('sp-a', 'inatPrimary'), isEmpty);
  });

  test('a real database error while processing a species is booked as its '
      'failed attempt and logged as a warning with its stack trace', () async {
    final warnings = recordPersistedWarnings();
    await seedSpecies('sp-a');
    when(
      speciesRepository.getSpecies(any),
    ).thenAnswer((_) async => {_species('sp-a')});
    when(
      baseImageEnrichmentService.downloadReferenceImages(any),
    ).thenAnswer((_) async {
      await database.rawQuery('SELECT * FROM no_such_table');
      return const BaseImageSaved();
    });

    final processedAny = await worker.runUntilIdle(shouldStop: () => false);

    expect(processedAny, isTrue);
    final base = await loadCapability('sp-a', 'base');
    expect(base['state'], 'retryScheduled');
    expect(base['attempt_count'], 1);
    expect(warnings, hasLength(1));
    expect(
      warnings.single,
      startsWith(
        '[BaseWorker] Base image download failed for sp-a — '
        'SqfliteFfiException: ',
      ),
    );
    expect(warnings.single, contains('no such table: no_such_table'));
    expect(warnings.single, contains('\n    #0 '));
  });

  test('a database closed while processing a species ends the loop without '
      'a warning and without booking an attempt', () async {
    final warnings = recordPersistedWarnings();
    final closed = await closedDatabaseException();
    await seedSpecies('sp-a');
    when(
      speciesRepository.getSpecies(any),
    ).thenAnswer((_) async => {_species('sp-a')});
    when(
      baseImageEnrichmentService.downloadReferenceImages(any),
    ).thenThrow(closed);

    final processedAny = await worker.runUntilIdle(shouldStop: () => false);

    expect(processedAny, isTrue);
    expect(warnings, isEmpty);
    final base = await loadCapability('sp-a', 'base');
    expect(base['state'], 'running');
    expect(base['attempt_count'], 0);
    verify(baseImageEnrichmentService.downloadReferenceImages(any)).called(1);
  });

  test('runUntilIdle ends quietly, reporting the work it claimed, when the '
      'user database is closed underneath it', () async {
    await seedSpecies('sp-a');
    when(speciesRepository.getSpecies(any)).thenAnswer((_) async {
      await database.close();
      await database.rawQuery('SELECT 1');
      return {_species('sp-a')};
    });

    final processedAny = await worker.runUntilIdle(shouldStop: () => false);

    expect(processedAny, isTrue);
    verifyNever(baseImageEnrichmentService.downloadReferenceImages(any));
  });

  test('runUntilIdle surfaces any other database error', () async {
    await seedSpecies('sp-a');
    when(speciesRepository.getSpecies(any)).thenAnswer((_) async {
      await database.rawQuery('SELECT * FROM no_such_table');
      return {_species('sp-a')};
    });

    await expectLater(
      worker.runUntilIdle(shouldStop: () => false),
      throwsA(
        isA<DatabaseException>().having(
          (e) => e.isNoSuchTableError('no_such_table'),
          'isNoSuchTableError',
          isTrue,
        ),
      ),
    );
  });

  test('runUntilIdle returns false when there is no claimable work', () async {
    final processedAny = await worker.runUntilIdle(shouldStop: () => false);
    expect(processedAny, isFalse);
    verifyNever(speciesRepository.getSpecies(any));
  });

  test('runUntilIdle stops early once shouldStop returns true', () async {
    await seedSpecies('sp-a');

    final processedAny = await worker.runUntilIdle(shouldStop: () => true);

    expect(processedAny, isFalse);
    verifyNever(speciesRepository.getSpecies(any));
    final base = await loadCapability('sp-a', 'base');
    expect(base['state'], 'pending');
  });

  test('processes multiple claimed species in one runUntilIdle call', () async {
    // A single call carrying both species for deck-1, not two separate
    // seedSpecies calls — assignSpeciesOwners prunes species missing from
    // the current call's input for a deck it's given, so seeding them one
    // at a time would delete sp-a's membership the moment sp-b is seeded.
    await ownershipRepository.assignSpeciesOwners(
      speciesIdsByDeckId: {
        'deck-1': {'sp-a', 'sp-b'},
      },
      prioritizedDeckIds: ['deck-1'],
    );
    when(speciesRepository.getSpecies(any)).thenAnswer((invocation) async {
      final ids = invocation.positionalArguments[0] as Set<String>;
      return ids.map((id) => _species(id)).toSet();
    });
    when(
      baseImageEnrichmentService.downloadReferenceImages(any),
    ).thenAnswer((_) async => const BaseImageSaved());

    final processedAny = await worker.runUntilIdle(shouldStop: () => false);

    expect(processedAny, isTrue);
    expect((await loadCapability('sp-a', 'base'))['state'], 'done');
    expect((await loadCapability('sp-b', 'base'))['state'], 'done');
  });
}
