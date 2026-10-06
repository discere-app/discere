import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/enrichment/pipeline/service/higher_taxon_id_resolver.dart';
import 'package:discere/enrichment/pipeline/service/taxonomy_common_name_enrichment_service.dart';
import 'package:discere/enrichment/pipeline/service/taxonomy_work_planner.dart';
import 'package:discere/external/inaturalist/models/inat_common_name.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../../../mocks.mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MockSpeciesRepository mockSpeciesRepo;
  late MockINatCommonNameApi mockINatService;
  late MockHigherTaxonIdResolver mockTaxonIds;
  late MockRuntimeCommonNameRepository mockRuntimeCommonNameRepo;
  late TaxonomyCommonNameEnrichmentService service;

  final barbel = Species(
    'sp1',
    '1',
    'fishbase',
    'barbus',
    const {},
    Classification(
      'Barbus',
      const {},
      null,
      'Cyprinidae',
      const {},
      'Cypriniformes',
      const {},
      'Actinopterygii',
      const {},
      null,
    ),
    const [],
  );

  const taxonIdsByRank = {
    'genus': 86989,
    'family': 51783,
    'order': 48051,
    'class': 47178,
  };

  setUp(() {
    mockSpeciesRepo = MockSpeciesRepository();
    mockINatService = MockINatCommonNameApi();
    mockTaxonIds = MockHigherTaxonIdResolver();
    mockRuntimeCommonNameRepo = MockRuntimeCommonNameRepository();
    // Mockito cannot invent a value of a sealed type for the stubbing call.
    provideDummy<HigherTaxonResolution>(const HigherTaxonAbsent());

    when(mockSpeciesRepo.getSpecies({'sp1'})).thenAnswer((_) async => {barbel});
    when(mockTaxonIds.knownTaxonId(any)).thenAnswer((_) async => null);
    when(mockTaxonIds.resolve(any, any)).thenAnswer(
      (invocation) async => HigherTaxonFound(
        taxonIdsByRank[(invocation.positionalArguments.first
                as TaxonomyPlanEntry)
            .rank]!,
      ),
    );
    when(
      mockRuntimeCommonNameRepo.getEntitiesWithStoredOutcome(any),
    ).thenAnswer((_) async => {});
    when(
      mockRuntimeCommonNameRepo.markNoCommonNames(
        entityKey: anyNamed('entityKey'),
        entityType: anyNamed('entityType'),
      ),
    ).thenAnswer((_) async {});
    when(
      mockRuntimeCommonNameRepo.saveTaxonomyCommonNamesBatch(any),
    ).thenAnswer((_) async {});

    service = TaxonomyCommonNameEnrichmentService(
      mockSpeciesRepo,
      mockINatService,
      mockTaxonIds,
      mockRuntimeCommonNameRepo,
    );
  });

  ({int taxonId, Map<String, List<INatCommonName>> commonNames}) namesFor(
    int taxonId,
  ) => (
    taxonId: taxonId,
    commonNames: <String, List<INatCommonName>>{
      'en': [INatCommonName(languageCode: 'en', name: 'Test name')],
    },
  );

  group('TaxonomyCommonNameEnrichmentService - fetching', () {
    test('fetches common names under the id the resolver found', () async {
      when(
        mockINatService.fetchCommonNames(any, taxonId: anyNamed('taxonId')),
      ).thenAnswer(
        (invocation) async =>
            namesFor(invocation.namedArguments[#taxonId] as int),
      );

      await service.fetchINatTaxonomyCommonNamesForSpecies({'sp1'});

      verify(
        mockINatService.fetchCommonNames('Barbus', taxonId: 86989),
      ).called(1);
      verify(
        mockINatService.fetchCommonNames('Cyprinidae', taxonId: 51783),
      ).called(1);
      verify(
        mockINatService.fetchCommonNames('Cypriniformes', taxonId: 48051),
      ).called(1);
      verify(
        mockINatService.fetchCommonNames('Actinopterygii', taxonId: 47178),
      ).called(1);
    });

    test('stores a no-result marker when iNaturalist has no such taxon, and '
        'counts it as done', () async {
      when(
        mockTaxonIds.resolve(any, any),
      ).thenAnswer((_) async => const HigherTaxonAbsent());

      final completed = <String>[];
      TaxonomyCommonNameDiagnostics? diagnostics;
      await service.fetchINatTaxonomyCommonNamesForEntityKeys(
        {'sp1'},
        entityKeys: ['genus:barbus'],
        onEntityCompleted: completed.add,
        onDiagnostics: (value) => diagnostics = value,
      );

      verify(
        mockRuntimeCommonNameRepo.markNoCommonNames(
          entityKey: 'genus:barbus',
          entityType: 'genera',
        ),
      ).called(1);
      verifyNever(
        mockINatService.fetchCommonNames(any, taxonId: anyNamed('taxonId')),
      );
      expect(completed, ['genus:barbus']);
      expect(diagnostics?.failedEntityKeys, isEmpty);
    });

    test(
      'stores a no-result marker when the taxon has no common names',
      () async {
        when(
          mockINatService.fetchCommonNames(any, taxonId: anyNamed('taxonId')),
        ).thenAnswer(
          (_) async =>
              (taxonId: 86989, commonNames: <String, List<INatCommonName>>{}),
        );

        final completed = <String>[];
        await service.fetchINatTaxonomyCommonNamesForEntityKeys(
          {'sp1'},
          entityKeys: ['genus:barbus'],
          onEntityCompleted: completed.add,
        );

        verify(
          mockRuntimeCommonNameRepo.markNoCommonNames(
            entityKey: 'genus:barbus',
            entityType: 'genera',
          ),
        ).called(1);
        expect(completed, ['genus:barbus']);
      },
    );

    test('a failed common-name request is left to retry, not recorded as '
        '"no names"', () async {
      when(
        mockINatService.fetchCommonNames(any, taxonId: anyNamed('taxonId')),
      ).thenAnswer((_) async => null);

      final completed = <String>[];
      TaxonomyCommonNameDiagnostics? diagnostics;
      await service.fetchINatTaxonomyCommonNamesForEntityKeys(
        {'sp1'},
        entityKeys: ['genus:barbus'],
        onEntityCompleted: completed.add,
        onDiagnostics: (value) => diagnostics = value,
      );

      verifyNever(
        mockRuntimeCommonNameRepo.markNoCommonNames(
          entityKey: anyNamed('entityKey'),
          entityType: anyNamed('entityType'),
        ),
      );
      expect(completed, isEmpty);
      expect(diagnostics?.failedEntityKeys, {'genus:barbus'});
      expect(diagnostics?.speciesIdsWithRemainingErrors, {'sp1'});
    });

    test(
      'a failed id lookup is left to retry, not recorded as "no names"',
      () async {
        when(
          mockTaxonIds.resolve(any, any),
        ).thenThrow(Exception('iNat unavailable'));

        final completed = <String>[];
        TaxonomyCommonNameDiagnostics? diagnostics;
        await service.fetchINatTaxonomyCommonNamesForEntityKeys(
          {'sp1'},
          entityKeys: ['genus:barbus'],
          onEntityCompleted: completed.add,
          onDiagnostics: (value) => diagnostics = value,
        );

        verifyNever(
          mockRuntimeCommonNameRepo.markNoCommonNames(
            entityKey: anyNamed('entityKey'),
            entityType: anyNamed('entityType'),
          ),
        );
        expect(completed, isEmpty);
        expect(diagnostics?.failedEntityKeys, {'genus:barbus'});
      },
    );
  });

  group('TaxonomyCommonNameEnrichmentService - work plan', () {
    test(
      'keys a taxon by its known iNaturalist id, else by its entity key',
      () async {
        when(
          mockTaxonIds.knownTaxonId('genus:barbus'),
        ).thenAnswer((_) async => 86989);

        final plan = await service.buildTaxonomyWorkPlanForSpecies({'sp1'});

        expect(
          {for (final item in plan) item.runtimeEntityKey: item.workKey},
          {
            'genus:barbus': 'genus:taxon:86989',
            'family:cyprinidae': 'family:cyprinidae',
            'order:cypriniformes': 'order:cypriniformes',
            'class:actinopterygii': 'class:actinopterygii',
          },
        );
      },
    );
  });
}
