import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/external_id_provider.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/enrichment/pipeline/repository/runtime_common_name_repository.dart';
import 'package:discere/enrichment/pipeline/service/inat_taxon_resolver.dart';
import 'package:discere/enrichment/pipeline/service/species_common_name_enrichment_service.dart';
import 'package:discere/enrichment/pipeline/service/taxonomy_common_name_enrichment_service.dart';
import 'package:discere/external/inaturalist/inaturalist_service.dart';
import 'package:discere/external/inaturalist/models/inat_common_name.dart';
import 'package:discere/shared/model/language.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../../../mocks.mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MockSpeciesRepository mockSpeciesRepo;
  late MockINaturalistService mockINatService;
  late MockExternalIdRepository mockExternalIdRepo;
  late MockExternalIdCacheRepository mockExternalIdCacheRepo;
  late MockRuntimeCommonNameRepository mockRuntimeCommonNameRepo;
  late SpeciesCommonNameEnrichmentService service;
  // Used alongside the species-level service in a couple of tests to verify
  // the combined `ImportEnrichmentSummary` both classes' callers add
  // together — species and taxonomy common names are always requested
  // together by INatWorker's reactive seeding.
  late TaxonomyCommonNameEnrichmentService taxonomyService;

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
      mockExternalIdRepo.getExternalIdsForProvider(any, any),
    ).thenAnswer((_) async => {});
    when(
      mockExternalIdCacheRepo.getExternalId(any, any),
    ).thenAnswer((_) async => null);
    when(
      mockExternalIdCacheRepo.getExternalIdsForProvider(any, any),
    ).thenAnswer((_) async => {});
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
      mockRuntimeCommonNameRepo.saveSpeciesCommonNamesBatch(any),
    ).thenAnswer((_) async {});
    when(
      mockRuntimeCommonNameRepo.saveTaxonomyCommonNamesBatch(any),
    ).thenAnswer((_) async {});
    when(
      mockSpeciesRepo.getScientificNameCandidates(
        any,
        preferredScientificName: anyNamed('preferredScientificName'),
      ),
    ).thenAnswer((invocation) async {
      final preferredScientificName =
          invocation.namedArguments[#preferredScientificName] as String?;
      if (preferredScientificName == null) return <String>[];
      return [preferredScientificName];
    });

    final taxonResolver = INatTaxonResolver(
      mockSpeciesRepo,
      mockExternalIdRepo,
      mockExternalIdCacheRepo,
    );
    service = SpeciesCommonNameEnrichmentService(
      mockSpeciesRepo,
      mockINatService,
      mockRuntimeCommonNameRepo,
      taxonResolver,
    );
    taxonomyService = TaxonomyCommonNameEnrichmentService(
      mockSpeciesRepo,
      mockINatService,
      mockExternalIdRepo,
      mockExternalIdCacheRepo,
      mockRuntimeCommonNameRepo,
    );
  });

  test(
    'persists species and taxonomy common names and returns combined summary',
    () async {
      final species = Species(
        'sp1',
        '1',
        'fishbase',
        'barbus',
        const {
          Language.de: ['Barbe'],
        },
        Classification(
          'Barbus',
          const {
            Language.en: ['Barbels'],
          },
          null,
          'Cyprinidae',
          const {
            Language.en: ['Minnows'],
          },
          'Cypriniformes',
          const {
            Language.en: ['Carps'],
          },
          'Actinopterygii',
          const {
            Language.en: ['Ray-finned fishes'],
          },
          null,
        ),
        const [],
      );

      when(
        mockSpeciesRepo.getSpecies({'sp1'}),
      ).thenAnswer((_) async => {species});
      when(
        mockINatService.fetchCommonNames(
          any,
          taxonId: anyNamed('taxonId'),
          rank: anyNamed('rank'),
        ),
      ).thenAnswer((invocation) async {
        final scientificName = invocation.positionalArguments.first as String;
        final rank = invocation.namedArguments[#rank] as String?;
        var taxonId = 999;

        if (rank == null) {
          return (
            taxonId: 101,
            commonNames: <String, List<INatCommonName>>{
              'en': [INatCommonName(languageCode: 'en', name: 'Common barbel')],
            },
          );
        }

        if (rank == 'genus') {
          taxonId = 201;
        } else if (rank == 'family') {
          taxonId = 202;
        } else if (rank == 'order') {
          taxonId = 203;
        } else if (rank == 'class') {
          taxonId = 204;
        }

        return (
          taxonId: taxonId,
          commonNames: <String, List<INatCommonName>>{
            'en': [
              INatCommonName(
                languageCode: 'en',
                name: '$scientificName common',
              ),
            ],
          },
        );
      });

      final speciesSummary = await service.fetchSpeciesCommonNamesForSpecies({
        'sp1',
      });
      final taxonomySummary = await taxonomyService
          .fetchINatTaxonomyCommonNamesForSpecies({'sp1'});
      final summary = speciesSummary + taxonomySummary;

      verify(
        mockRuntimeCommonNameRepo.saveSpeciesCommonNamesBatch(
          argThat(
            predicate(
              (dynamic records) =>
                  records is Map<Species, Map<String, List<INatCommonName>>> &&
                  records.length == 1 &&
                  records.keys.single.id == 'sp1' &&
                  records.values.single['en']?.single.name == 'Common barbel',
            ),
          ),
        ),
      ).called(1);

      final taxonomyRecords =
          verify(
                mockRuntimeCommonNameRepo.saveTaxonomyCommonNamesBatch(
                  captureAny,
                ),
              ).captured.single
              as Iterable<RuntimeTaxonomyCommonNameRecord>;
      expect(taxonomyRecords.map((record) => record.entityKey).toSet(), {
        'genus:barbus',
        'family:cyprinidae',
        'order:cypriniformes',
        'class:actinopterygii',
      });
      expect(
        taxonomyRecords
            .where((record) => record.entityKey == 'genus:barbus')
            .single
            .referenceCommonNames,
        const {
          Language.en: ['Barbels'],
        },
      );

      expect(summary.commonNameSpeciesCount, 5);
      expect(summary.commonNameCount, 5);
    },
  );

  test(
    'falls back to alternate scientific names when species common-name lookup fails',
    () async {
      final species = Species(
        'sp1',
        '1',
        'sealifebase',
        'depressa',
        const {},
        Classification(
          'Natator',
          const {},
          null,
          'Cheloniidae',
          const {},
          'Testudines',
          const {},
          'Reptilia',
          const {},
          null,
        ),
        const [],
      );

      when(
        mockSpeciesRepo.getSpecies({'sp1'}),
      ).thenAnswer((_) async => {species});
      when(
        mockSpeciesRepo.getScientificNameCandidates(
          'sp1',
          preferredScientificName: 'Natator depressa',
        ),
      ).thenAnswer((_) async => ['Natator depressa', 'Natator depressus']);
      when(
        mockINatService.fetchCommonNames(
          'Natator depressa',
          taxonId: anyNamed('taxonId'),
          rank: anyNamed('rank'),
        ),
      ).thenAnswer((_) async => null);
      when(
        mockINatService.fetchCommonNames(
          'Natator depressus',
          taxonId: anyNamed('taxonId'),
          rank: anyNamed('rank'),
        ),
      ).thenAnswer(
        (_) async => (
          taxonId: 701,
          commonNames: <String, List<INatCommonName>>{
            'en': [
              INatCommonName(languageCode: 'en', name: 'Flatback sea turtle'),
            ],
          },
        ),
      );
      when(
        mockINatService.fetchCommonNames(
          any,
          taxonId: anyNamed('taxonId'),
          rank: 'genus',
        ),
      ).thenAnswer((_) async => null);
      when(
        mockINatService.fetchCommonNames(
          any,
          taxonId: anyNamed('taxonId'),
          rank: 'family',
        ),
      ).thenAnswer((_) async => null);
      when(
        mockINatService.fetchCommonNames(
          any,
          taxonId: anyNamed('taxonId'),
          rank: 'order',
        ),
      ).thenAnswer((_) async => null);
      when(
        mockINatService.fetchCommonNames(
          any,
          taxonId: anyNamed('taxonId'),
          rank: 'class',
        ),
      ).thenAnswer((_) async => null);

      final speciesSummary = await service.fetchSpeciesCommonNamesForSpecies({
        'sp1',
      });
      final taxonomySummary = await taxonomyService
          .fetchINatTaxonomyCommonNamesForSpecies({'sp1'});
      final summary = speciesSummary + taxonomySummary;

      verifyInOrder([
        mockINatService.fetchCommonNames(
          'Natator depressa',
          taxonId: null,
          rank: null,
        ),
        mockINatService.fetchCommonNames(
          'Natator depressus',
          taxonId: null,
          rank: null,
        ),
      ]);
      verify(
        mockExternalIdCacheRepo.saveExternalId(
          'sp1',
          ExternalIdProvider.inaturalist,
          '701',
        ),
      ).called(1);
      expect(summary.commonNameSpeciesCount, greaterThanOrEqualTo(1));
    },
  );

  test(
    'stores an explicit no-result marker when iNat resolves but has no common names',
    () async {
      final species = Species(
        'sp1',
        '1',
        'sealifebase',
        'depressa',
        const {},
        Classification(
          'Natator',
          const {},
          null,
          'Cheloniidae',
          const {},
          'Testudines',
          const {},
          'Reptilia',
          const {},
          null,
        ),
        const [],
      );

      when(
        mockSpeciesRepo.getSpecies({'sp1'}),
      ).thenAnswer((_) async => {species});
      when(
        mockINatService.fetchCommonNames(
          'Natator depressa',
          taxonId: anyNamed('taxonId'),
          rank: anyNamed('rank'),
        ),
      ).thenAnswer(
        (_) async =>
            (taxonId: 703, commonNames: <String, List<INatCommonName>>{}),
      );
      when(
        mockINatService.fetchCommonNames(
          any,
          taxonId: anyNamed('taxonId'),
          rank: 'genus',
        ),
      ).thenAnswer((_) async => null);
      when(
        mockINatService.fetchCommonNames(
          any,
          taxonId: anyNamed('taxonId'),
          rank: 'family',
        ),
      ).thenAnswer((_) async => null);
      when(
        mockINatService.fetchCommonNames(
          any,
          taxonId: anyNamed('taxonId'),
          rank: 'order',
        ),
      ).thenAnswer((_) async => null);
      when(
        mockINatService.fetchCommonNames(
          any,
          taxonId: anyNamed('taxonId'),
          rank: 'class',
        ),
      ).thenAnswer((_) async => null);

      final speciesSummary = await service.fetchSpeciesCommonNamesForSpecies({
        'sp1',
      });
      final taxonomySummary = await taxonomyService
          .fetchINatTaxonomyCommonNamesForSpecies({'sp1'});
      final summary = speciesSummary + taxonomySummary;

      verify(
        mockRuntimeCommonNameRepo.markNoCommonNames(
          entityKey: 'species:sp1',
          entityType: 'species',
        ),
      ).called(1);
      expect(summary.commonNameSpeciesCount, 0);
      expect(summary.commonNameCount, 0);
    },
  );

  test(
    'stores an explicit no-result marker when the taxon is confirmed unresolvable '
    'instead of retrying forever',
    () async {
      final species = Species(
        'sp1',
        '1',
        'sealifebase',
        'depressa',
        const {},
        Classification(
          'Natator',
          const {},
          null,
          'Cheloniidae',
          const {},
          'Testudines',
          const {},
          'Reptilia',
          const {},
          null,
        ),
        const [],
      );

      when(
        mockSpeciesRepo.getSpecies({'sp1'}),
      ).thenAnswer((_) async => {species});
      when(
        mockINatService.fetchCommonNames(
          'Natator depressa',
          taxonId: anyNamed('taxonId'),
          rank: anyNamed('rank'),
        ),
      ).thenThrow(const TaxonNotFoundException('Natator depressa'));

      final completedSpeciesIds = <String>[];
      final speciesSummary = await service.fetchSpeciesCommonNamesForSpecies({
        'sp1',
      }, onSpeciesCompleted: completedSpeciesIds.add);

      verify(
        mockRuntimeCommonNameRepo.markNoCommonNames(
          entityKey: 'species:sp1',
          entityType: 'species',
        ),
      ).called(1);
      expect(completedSpeciesIds, ['sp1']);
      expect(speciesSummary.commonNameSpeciesCount, 0);
      expect(speciesSummary.commonNameCount, 0);
    },
  );
}
