import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/external_id_provider.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/enrichment/service/taxonomy_common_name_enrichment_service.dart';
import 'package:discere/external/inaturalist/models/inat_common_name.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../../mocks.mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MockSpeciesRepository mockSpeciesRepo;
  late MockINaturalistService mockINatService;
  late MockExternalIdRepository mockExternalIdRepo;
  late MockExternalIdCacheRepository mockExternalIdCacheRepo;
  late MockRuntimeCommonNameRepository mockRuntimeCommonNameRepo;
  late TaxonomyCommonNameEnrichmentService service;

  setUp(() {
    mockSpeciesRepo = MockSpeciesRepository();
    mockINatService = MockINaturalistService();
    mockExternalIdRepo = MockExternalIdRepository();
    mockExternalIdCacheRepo = MockExternalIdCacheRepository();
    mockRuntimeCommonNameRepo = MockRuntimeCommonNameRepository();

    when(
      mockExternalIdRepo.getExternalId(any, any),
    ).thenAnswer((_) async => null);
    when(
      mockExternalIdCacheRepo.getExternalId(any, any),
    ).thenAnswer((_) async => null);
    when(
      mockExternalIdCacheRepo.saveExternalId(any, any, any),
    ).thenAnswer((_) async {});
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
      mockExternalIdRepo,
      mockExternalIdCacheRepo,
      mockRuntimeCommonNameRepo,
    );
  });

  group('TaxonomyCommonNameEnrichmentService - taxonomy iNat IDs', () {
    test(
      'uses ETL-provided taxonomy external IDs before live resolve',
      () async {
        when(mockSpeciesRepo.getSpecies({'sp1'})).thenAnswer(
          (_) async => {
            Species(
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
            ),
          },
        );
        when(
          mockExternalIdRepo.getExternalId('genus:barbus', ExternalIdProvider.inaturalist),
        ).thenAnswer((_) async => '86989');
        when(
          mockExternalIdRepo.getExternalId('family:cyprinidae', ExternalIdProvider.inaturalist),
        ).thenAnswer((_) async => '51783');
        when(
          mockExternalIdRepo.getExternalId(
            'order:cypriniformes',
            ExternalIdProvider.inaturalist,
          ),
        ).thenAnswer((_) async => '48051');
        when(
          mockExternalIdRepo.getExternalId(
            'class:actinopterygii',
            ExternalIdProvider.inaturalist,
          ),
        ).thenAnswer((_) async => '47178');
        when(
          mockINatService.fetchCommonNames(
            any,
            taxonId: anyNamed('taxonId'),
            rank: anyNamed('rank'),
          ),
        ).thenAnswer(
          (_) async => (
            taxonId: 1,
            commonNames: <String, List<INatCommonName>>{
              'en': [INatCommonName(languageCode: 'en', name: 'Test name')],
            },
          ),
        );

        await service.fetchINatTaxonomyCommonNamesForSpecies({'sp1'});

        verify(
          mockINatService.fetchCommonNames(
            'Barbus',
            taxonId: 86989,
            rank: 'genus',
          ),
        ).called(1);
        verify(
          mockINatService.fetchCommonNames(
            'Cyprinidae',
            taxonId: 51783,
            rank: 'family',
          ),
        ).called(1);
        verify(
          mockINatService.fetchCommonNames(
            'Cypriniformes',
            taxonId: 48051,
            rank: 'order',
          ),
        ).called(1);
        verify(
          mockINatService.fetchCommonNames(
            'Actinopterygii',
            taxonId: 47178,
            rank: 'class',
          ),
        ).called(1);
      },
    );

    test(
      'caches runtime-resolved taxonomy external IDs with taxonomy keys',
      () async {
        when(mockSpeciesRepo.getSpecies({'sp1'})).thenAnswer(
          (_) async => {
            Species(
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
            ),
          },
        );
        when(
          mockINatService.fetchCommonNames(
            any,
            taxonId: anyNamed('taxonId'),
            rank: anyNamed('rank'),
          ),
        ).thenAnswer(
          (invocation) async => (
            taxonId: invocation.namedArguments[#rank] == 'genus'
                ? 86989
                : 51783,
            commonNames: <String, List<INatCommonName>>{
              'en': [INatCommonName(languageCode: 'en', name: 'Test name')],
            },
          ),
        );

        await service.fetchINatTaxonomyCommonNamesForSpecies({'sp1'});

        verify(
          mockExternalIdCacheRepo.saveExternalId(
            'genus:barbus',
            ExternalIdProvider.inaturalist,
            '86989',
          ),
        ).called(1);
      },
    );
  });
}
