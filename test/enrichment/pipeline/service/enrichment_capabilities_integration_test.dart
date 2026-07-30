import 'dart:convert';

import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/enrichment/pipeline/service/inat_photo_enrichment_service.dart';
import 'package:discere/enrichment/pipeline/service/inat_taxon_resolver.dart';
import 'package:discere/enrichment/pipeline/service/species_common_name_enrichment_service.dart';
import 'package:discere/enrichment/pipeline/service/taxonomy_common_name_enrichment_service.dart';
import 'package:discere/external/inaturalist/inaturalist_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mockito/mockito.dart';

import '../../../mocks.mocks.dart';

/// Cross-service integration coverage: `INatPhotoEnrichmentService`,
/// `SpeciesCommonNameEnrichmentService`, and `TaxonomyCommonNameEnrichmentService`
/// are all reactively invoked together for the same species by `INatWorker`
/// (see `lib/enrichment/service/inat_worker.dart`), so this exercises them
/// together against a real `INaturalistService` (fake HTTP transport) rather
/// than duplicating one-off mocked coverage per class — a regression test for
/// the V2/legacy endpoint split, not a unit test of any single service.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MockSpeciesRepository mockSpeciesRepo;
  late MockImageService mockImageService;
  late MockINatPhotoCacheRepository mockINatCacheRepo;
  late MockExternalIdRepository mockExternalIdRepo;
  late MockExternalIdCacheRepository mockExternalIdCacheRepo;
  late MockRuntimeCommonNameRepository mockRuntimeCommonNameRepo;

  setUp(() {
    mockSpeciesRepo = MockSpeciesRepository();
    mockImageService = MockImageService();
    mockINatCacheRepo = MockINatPhotoCacheRepository();
    mockExternalIdRepo = MockExternalIdRepository();
    mockExternalIdCacheRepo = MockExternalIdCacheRepository();
    mockRuntimeCommonNameRepo = MockRuntimeCommonNameRepository();

    when(
      mockImageService.downloadAndSaveUrlMap(
        any,
        storageDirectory: anyNamed('storageDirectory'),
        maxConcurrent: anyNamed('maxConcurrent'),
        onProgress: anyNamed('onProgress'),
      ),
    ).thenAnswer((_) async => <String, String>{});
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
    when(mockINatCacheRepo.getCachedPhotos(any)).thenAnswer((_) async => null);
    when(mockINatCacheRepo.cachePhotos(any, any)).thenAnswer((_) async {});
  });

  test(
    'runs photo, species-name and taxonomy-name enrichment through V2 plus legacy common-name endpoint',
    () async {
      final alpha = Species(
        'sp-alpha',
        '1',
        'fishbase',
        'alpha',
        const {},
        Classification(
          'Specius',
          const {},
          null,
          'Sharedidae',
          const {},
          'Sharediformes',
          const {},
          'Actinopterygii',
          const {},
          null,
        ),
        const [],
      );
      final beta = Species(
        'sp-beta',
        '2',
        'fishbase',
        'beta',
        const {},
        Classification(
          'Specius',
          const {},
          null,
          'Sharedidae',
          const {},
          'Sharediformes',
          const {},
          'Actinopterygii',
          const {},
          null,
        ),
        const [],
      );
      final requests = <Uri>[];

      final client = MockClient((request) async {
        requests.add(request.url);

        if (request.url.host == 'api.inaturalist.org' &&
            request.url.path == '/v2/taxa') {
          final query = request.url.queryParameters['q'];
          final rank =
              request.url.queryParametersAll['rank']?.single ??
              request.url.queryParameters['rank'];
          final taxonIdByKey = <String, int>{
            'Specius alpha|species': 1001,
            'Specius beta|species': 1002,
            'Specius|genus': 2001,
            'Sharedidae|family': 2002,
            'Sharediformes|order': 2003,
            'Actinopterygii|class': 2004,
          };
          final id = taxonIdByKey['$query|$rank'];
          return http.Response(
            jsonEncode({
              'results': id == null
                  ? const []
                  : [
                      {
                        'id': id,
                        'name': query,
                        'rank': rank,
                        'matched_term': query,
                      },
                    ],
            }),
            200,
          );
        }

        if (request.url.host == 'api.inaturalist.org' &&
            request.url.path == '/v2/taxa/1001') {
          return http.Response(
            jsonEncode({
              'results': [
                {'id': 1001, 'name': 'Specius alpha', 'taxon_photos': []},
              ],
            }),
            200,
          );
        }

        if (request.url.host == 'api.inaturalist.org' &&
            request.url.path == '/v2/taxa/1002') {
          return http.Response(
            jsonEncode({
              'results': [
                {'id': 1002, 'name': 'Specius beta', 'taxon_photos': []},
              ],
            }),
            200,
          );
        }

        if (request.url.host == 'api.inaturalist.org' &&
            request.url.path == '/v2/observations') {
          final taxonId =
              request.url.queryParametersAll['taxon_id']?.single ??
              request.url.queryParameters['taxon_id'];
          return http.Response(
            jsonEncode({
              'results': [
                {
                  'observation_photos': [
                    {
                      'photo': {
                        'url':
                            'https://static.inaturalist.org/photos/$taxonId/square.jpeg',
                        'license_code': 'cc-by',
                      },
                    },
                  ],
                },
              ],
            }),
            200,
          );
        }

        if (request.url.host == 'www.inaturalist.org' &&
            request.url.path == '/taxon_names.json') {
          final taxonId = request.url.queryParameters['taxon_id'];
          return http.Response(
            jsonEncode([
              {
                'name': 'Common name $taxonId',
                'lexicon': 'English',
                'position': 1,
              },
            ]),
            200,
          );
        }

        return http.Response('', 404);
      });

      final integratedINatService = INaturalistService(client: client);
      final integratedTaxonResolver = INatTaxonResolver(
        mockSpeciesRepo,
        mockExternalIdRepo,
        mockExternalIdCacheRepo,
      );
      final integratedPhotoService = INatPhotoEnrichmentService(
        mockSpeciesRepo,
        integratedINatService,
        mockINatCacheRepo,
        mockImageService,
        mockExternalIdCacheRepo,
        integratedTaxonResolver,
      );
      final integratedCommonNameService = SpeciesCommonNameEnrichmentService(
        mockSpeciesRepo,
        integratedINatService,
        mockRuntimeCommonNameRepo,
        integratedTaxonResolver,
      );
      final integratedTaxonomyService = TaxonomyCommonNameEnrichmentService(
        mockSpeciesRepo,
        integratedINatService,
        mockExternalIdRepo,
        mockExternalIdCacheRepo,
        mockRuntimeCommonNameRepo,
      );

      when(
        mockSpeciesRepo.getSpecies({'sp-alpha', 'sp-beta'}),
      ).thenAnswer((_) async => {alpha, beta});
      when(
        mockSpeciesRepo.getScientificNameCandidates(
          'sp-alpha',
          preferredScientificName: 'Specius alpha',
        ),
      ).thenAnswer((_) async => ['Specius alpha']);
      when(
        mockSpeciesRepo.getScientificNameCandidates(
          'sp-beta',
          preferredScientificName: 'Specius beta',
        ),
      ).thenAnswer((_) async => ['Specius beta']);

      final photoSummary = await integratedPhotoService
          .fetchINatPhotosForSpecies({
            'sp-alpha',
            'sp-beta',
          }, primaryOnly: false);
      final speciesNameSummary = await integratedCommonNameService
          .fetchSpeciesCommonNamesForSpecies({'sp-alpha', 'sp-beta'});
      final workPlan = await integratedTaxonomyService
          .buildTaxonomyWorkPlanForSpecies({'sp-alpha', 'sp-beta'});
      final taxonomySummary = await integratedTaxonomyService
          .fetchINatTaxonomyCommonNamesForEntityKeys(
            {'sp-alpha', 'sp-beta'},
            entityKeys: workPlan.map((item) => item.runtimeEntityKey),
            maxConcurrent: 1,
          );

      expect(photoSummary.imageSpeciesCount, 2);
      expect(photoSummary.imageCount, 2);
      expect(speciesNameSummary.commonNameSpeciesCount, 2);
      expect(taxonomySummary.commonNameSpeciesCount, 4);

      verify(
        mockRuntimeCommonNameRepo.saveSpeciesCommonNamesBatch(
          argThat(hasLength(2)),
        ),
      ).called(1);
      verify(
        mockRuntimeCommonNameRepo.saveTaxonomyCommonNamesBatch(
          argThat(hasLength(4)),
        ),
      ).called(1);

      expect(requests.where((uri) => uri.path == '/v2/taxa'), isNotEmpty);
      expect(
        requests.where((uri) => uri.path == '/v2/taxa/1001'),
        hasLength(1),
      );
      expect(
        requests.where((uri) => uri.path == '/v2/taxa/1002'),
        hasLength(1),
      );
      expect(
        requests.where((uri) => uri.path == '/v2/observations'),
        hasLength(2),
      );
      expect(
        requests.where((uri) => uri.path == '/taxon_names.json'),
        hasLength(6),
      );
      expect(requests.any((uri) => uri.path.startsWith('/v1/')), isFalse);
    },
  );
}
