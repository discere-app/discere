import 'dart:convert';

import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/external_id_provider.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/enrichment/pipeline/service/higher_taxon_id_resolver.dart';
import 'package:discere/enrichment/pipeline/service/inat_taxon_resolver.dart';
import 'package:discere/enrichment/pipeline/service/taxonomy_work_planner.dart';
import 'package:discere/enrichment/service/enrichment_failure_classifier.dart';
import 'package:discere/external/inaturalist/inat_api_client.dart';
import 'package:discere/external/inaturalist/inat_taxon_details.dart';
import 'package:discere/external/inaturalist/inat_taxon_id_resolver.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mockito/mockito.dart';

import '../../../mocks.mocks.dart';

/// The great white shark's ancestry from class down, as iNaturalist sends
/// it: Elasmobranchii is a subclass there.
const _sharkAncestry = [
  {'id': 196614, 'name': 'Chondrichthyes', 'rank': 'class'},
  {'id': 47273, 'name': 'Elasmobranchii', 'rank': 'subclass'},
  {'id': 50870, 'name': 'Lamniformes', 'rank': 'order'},
  {'id': 50874, 'name': 'Lamnidae', 'rank': 'family'},
  {'id': 50875, 'name': 'Carcharodon', 'rank': 'genus'},
];

const _elasmobranchii = TaxonomyPlanEntry(
  runtimeEntityKey: 'class:elasmobranchii',
  rank: 'class',
  scientificName: 'Elasmobranchii',
  entityId: null,
  speciesIds: {'sp1', 'sp2'},
);

const _holocephali = TaxonomyPlanEntry(
  runtimeEntityKey: 'class:holocephali',
  rank: 'class',
  scientificName: 'Holocephali',
  entityId: null,
  speciesIds: {'sp1'},
);

Species _species(String id) => Species(
  id,
  id,
  'fishbase',
  'carcharias',
  const {},
  Classification(
    'Carcharodon',
    const {},
    null,
    'Lamnidae',
    const {},
    'Lamniformes',
    const {},
    'Elasmobranchii',
    const {},
    null,
  ),
  const [],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MockExternalIdRepository mockExternalIdRepo;
  late MockExternalIdCacheRepository mockExternalIdCacheRepo;
  late List<http.Request> requests;
  late Map<String, int> speciesTaxonIds;
  late int detailStatus;
  late int searchStatus;
  late List<Map<String, Object>> searchResults;
  late HigherTaxonIdResolver resolver;

  /// Every species taxon id the detail endpoint was asked for.
  List<String> requestedDetailIds() => [
    for (final request in requests)
      if (request.url.path.startsWith('/v2/taxa/'))
        ...request.url.pathSegments.last.split(','),
  ];

  Iterable<http.Request> searches() =>
      requests.where((request) => request.url.path == '/v2/taxa');

  setUp(() {
    mockExternalIdRepo = MockExternalIdRepository();
    mockExternalIdCacheRepo = MockExternalIdCacheRepository();
    requests = [];
    speciesTaxonIds = {};
    detailStatus = 200;
    searchStatus = 200;
    searchResults = [];

    when(
      mockExternalIdRepo.getExternalId(any, any),
    ).thenAnswer((_) async => null);
    when(mockExternalIdRepo.getExternalIdsForProvider(any, any)).thenAnswer(
      (invocation) async => {
        for (final id in invocation.positionalArguments.first as Set<String>)
          id: ?speciesTaxonIds[id],
      },
    );
    when(
      mockExternalIdCacheRepo.getExternalId(any, any),
    ).thenAnswer((_) async => null);
    when(
      mockExternalIdCacheRepo.getExternalIdsForProvider(any, any),
    ).thenAnswer((_) async => {});
    when(
      mockExternalIdCacheRepo.saveExternalId(any, any, any),
    ).thenAnswer((_) async {});

    final client = MockClient((request) async {
      requests.add(request);
      if (request.url.path == '/v2/taxa') {
        return http.Response(
          jsonEncode({'results': searchResults}),
          searchStatus,
        );
      }
      final ids = request.url.pathSegments.last.split(',').map(int.parse);
      return http.Response(
        jsonEncode({
          'results': [
            for (final id in ids) {'id': id, 'ancestors': _sharkAncestry},
          ],
        }),
        detailStatus,
      );
    });
    final api = INatApiClient(client: client);
    resolver = HigherTaxonIdResolver(
      mockExternalIdRepo,
      mockExternalIdCacheRepo,
      INatTaxonResolver(
        MockSpeciesRepository(),
        mockExternalIdRepo,
        mockExternalIdCacheRepo,
      ),
      INatTaxonDetails(api: api),
      INatTaxonIdResolver(api: api),
    );
  });

  test(
    'takes the reference database\'s id without asking iNaturalist',
    () async {
      when(
        mockExternalIdRepo.getExternalId(
          'class:elasmobranchii',
          ExternalIdProvider.inaturalist,
        ),
      ).thenAnswer((_) async => '12345');
      when(
        mockExternalIdCacheRepo.getExternalId(
          'class:elasmobranchii',
          ExternalIdProvider.inaturalist,
        ),
      ).thenAnswer((_) async => '99999');
      speciesTaxonIds = {'sp1': 50873};

      final resolution = await resolver.resolve(_elasmobranchii, [
        _species('sp1'),
      ]);

      expect(
        resolution,
        isA<HigherTaxonFound>().having((r) => r.taxonId, 'taxonId', 12345),
      );
      expect(requests, isEmpty);
      verifyNever(mockExternalIdCacheRepo.saveExternalId(any, any, any));
    },
  );

  test('takes a cached id without asking iNaturalist', () async {
    when(
      mockExternalIdCacheRepo.getExternalId(
        'class:elasmobranchii',
        ExternalIdProvider.inaturalist,
      ),
    ).thenAnswer((_) async => '47273');
    speciesTaxonIds = {'sp1': 50873};

    final resolution = await resolver.resolve(_elasmobranchii, [
      _species('sp1'),
    ]);

    expect(
      resolution,
      isA<HigherTaxonFound>().having((r) => r.taxonId, 'taxonId', 47273),
    );
    expect(requests, isEmpty);
  });

  test('finds the taxon in a species\' ancestry and caches its id', () async {
    speciesTaxonIds = {'sp1': 50873};

    final resolution = await resolver.resolve(_elasmobranchii, [
      _species('sp1'),
    ]);

    expect(
      resolution,
      isA<HigherTaxonFound>().having((r) => r.taxonId, 'taxonId', 47273),
    );
    expect(searches(), isEmpty);
    verify(
      mockExternalIdCacheRepo.saveExternalId(
        'class:elasmobranchii',
        ExternalIdProvider.inaturalist,
        '47273',
      ),
    ).called(1);
  });

  test('searches by exact name when no ancestry names the taxon', () async {
    speciesTaxonIds = {'sp1': 50873};
    searchResults = [
      {'id': 60450, 'name': 'Holocephali', 'rank': 'class'},
    ];

    final resolution = await resolver.resolve(_holocephali, [_species('sp1')]);

    expect(
      resolution,
      isA<HigherTaxonFound>().having((r) => r.taxonId, 'taxonId', 60450),
    );
    expect(requestedDetailIds(), ['50873']);
    expect(searches().single.url.queryParameters['q'], 'Holocephali');
    verify(
      mockExternalIdCacheRepo.saveExternalId(
        'class:holocephali',
        ExternalIdProvider.inaturalist,
        '60450',
      ),
    ).called(1);
  });

  test('is absent when neither the ancestry nor the search has it', () async {
    speciesTaxonIds = {'sp1': 50873};

    final resolution = await resolver.resolve(_holocephali, [_species('sp1')]);

    expect(resolution, isA<HigherTaxonAbsent>());
    verifyNever(mockExternalIdCacheRepo.saveExternalId(any, any, any));
  });

  test('reads the ancestry of at most thirty species', () async {
    final speciesIds = [
      for (var i = 0; i < 40; i++) 'sp${i.toString().padLeft(2, '0')}',
    ];
    speciesTaxonIds = {for (final (i, id) in speciesIds.indexed) id: 1000 + i};
    final target = TaxonomyPlanEntry(
      runtimeEntityKey: 'class:holocephali',
      rank: 'class',
      scientificName: 'Holocephali',
      entityId: null,
      speciesIds: speciesIds.toSet(),
    );

    await resolver.resolve(target, [
      for (final id in speciesIds.reversed) _species(id),
    ]);

    expect(requestedDetailIds(), [for (var i = 0; i < 30; i++) '${1000 + i}']);
  });

  test('skips species without an iNaturalist id and species outside the '
      'taxon', () async {
    speciesTaxonIds = {'sp1': 50873, 'sp3': 50999};

    await resolver.resolve(_holocephali, [
      _species('sp1'),
      _species('sp2'),
      _species('sp3'),
    ]);

    expect(requestedDetailIds(), ['50873']);
  });

  test(
    'a failed ancestry request is an error to retry, not an absence',
    () async {
      speciesTaxonIds = {'sp1': 50873};
      detailStatus = 503;

      await expectLater(
        resolver.resolve(_holocephali, [_species('sp1')]),
        throwsA(
          predicate(
            (Object e) =>
                classifyEnrichmentFailure(e) == EnrichmentFailureKind.temporary,
          ),
        ),
      );
      expect(searches(), isEmpty);
      verifyNever(mockExternalIdCacheRepo.saveExternalId(any, any, any));
    },
  );

  test('a failed search is an error to retry, not an absence', () async {
    speciesTaxonIds = {'sp1': 50873};
    searchStatus = 503;

    await expectLater(
      resolver.resolve(_holocephali, [_species('sp1')]),
      throwsA(
        predicate(
          (Object e) =>
              classifyEnrichmentFailure(e) == EnrichmentFailureKind.temporary,
        ),
      ),
    );
  });

  test('knownTaxonId prefers the reference database over the cache', () async {
    when(
      mockExternalIdRepo.getExternalId(
        'genus:barbus',
        ExternalIdProvider.inaturalist,
      ),
    ).thenAnswer((_) async => '86989');
    when(
      mockExternalIdCacheRepo.getExternalId(
        'genus:barbus',
        ExternalIdProvider.inaturalist,
      ),
    ).thenAnswer((_) async => '1');
    when(
      mockExternalIdCacheRepo.getExternalId(
        'family:cyprinidae',
        ExternalIdProvider.inaturalist,
      ),
    ).thenAnswer((_) async => '51783');

    expect(await resolver.knownTaxonId('genus:barbus'), 86989);
    expect(await resolver.knownTaxonId('family:cyprinidae'), 51783);
    expect(await resolver.knownTaxonId('order:cypriniformes'), isNull);
  });
}
