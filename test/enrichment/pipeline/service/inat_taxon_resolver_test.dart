import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/external_id_provider.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/enrichment/pipeline/service/inat_taxon_resolver.dart';
import 'package:discere/external/inaturalist/inat_ancestry_requirement.dart';
import 'package:discere/external/inaturalist/inat_taxon_id_resolver.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../../../mocks.mocks.dart';

const _gastropoda = 'discere:class:1';

/// Mollusca, as iNaturalist numbers it.
const _molluscs = INatAncestryRequirement([
  {47115},
]);

Species _species({required String? genus, String? classId = _gastropoda}) =>
    Species(
      'sp1',
      'sp1',
      'sealifebase',
      'pusilla',
      const {},
      Classification(
        genus,
        const {},
        null,
        null,
        const {},
        null,
        const {},
        null,
        const {},
        null,
        classId: classId,
      ),
      const [],
    );

void main() {
  late MockSpeciesRepository speciesRepository;
  late MockExternalIdRepository externalIds;
  late MockExternalIdCacheRepository cachedIds;
  late MockExternalIdRejectionRepository rejections;
  late MockINatAllowedAncestorRepository allowedAncestors;
  late MockINatTaxonIdResolver taxonIds;
  late INatTaxonResolver resolver;

  setUp(() {
    speciesRepository = MockSpeciesRepository();
    externalIds = MockExternalIdRepository();
    cachedIds = MockExternalIdCacheRepository();
    rejections = MockExternalIdRejectionRepository();
    allowedAncestors = MockINatAllowedAncestorRepository();
    taxonIds = MockINatTaxonIdResolver();
    resolver = INatTaxonResolver(
      speciesRepository,
      externalIds,
      cachedIds,
      rejections,
      allowedAncestors,
      taxonIds,
    );
    when(
      speciesRepository.getScientificNameCandidates(
        any,
        preferredScientificName: anyNamed('preferredScientificName'),
      ),
    ).thenAnswer((_) async => const []);
    when(rejections.isRejected(any, any)).thenAnswer((_) async => false);
    when(
      allowedAncestors.requirementForSpecies(any),
    ).thenAnswer((_) async => _molluscs);
  });

  test(
    'falls back to the binomial when the reference DB has no names',
    () async {
      expect(
        await resolver.scientificNameCandidates(
          _species(genus: 'Amakusaplana'),
        ),
        ['Amakusaplana pusilla'],
      );
    },
  );

  test('has no candidate for a species without a genus: its epithet alone '
      'would find whichever species shares it', () async {
    expect(
      await resolver.scientificNameCandidates(_species(genus: null)),
      isEmpty,
    );
  });

  group('knownTaxonId', () {
    void givenReferenceIds(Map<String, int> ids) => when(
      externalIds.getExternalIdsForProvider(
        any,
        ExternalIdProvider.inaturalist,
      ),
    ).thenAnswer((_) async => ids);

    void givenCachedIds(Map<String, int> ids) => when(
      cachedIds.getExternalIdsForProvider(any, ExternalIdProvider.inaturalist),
    ).thenAnswer((_) async => ids);

    test('prefers the reference database over the cache', () async {
      givenReferenceIds({'sp1': 47});
      givenCachedIds({'sp1': 48});

      expect(await resolver.knownTaxonId('sp1'), 47);
    });

    test('falls back to an id found earlier', () async {
      givenReferenceIds(const {});
      givenCachedIds({'sp1': 48});

      expect(await resolver.knownTaxonId('sp1'), 48);
    });

    test('is null when neither has one', () async {
      givenReferenceIds(const {});
      givenCachedIds(const {});

      expect(await resolver.knownTaxonId('sp1'), isNull);
    });
  });

  group('searchTaxonId', () {
    void givenSearch(String name, Future<int?> Function() answer) {
      when(
        taxonIds.resolve(name, ancestry: anyNamed('ancestry')),
      ).thenAnswer((_) => answer());
    }

    test('searches each name against the phyla of the species\' class', () async {
      when(
        speciesRepository.getScientificNameCandidates(
          'sp1',
          preferredScientificName: 'Triphora pusilla',
        ),
      ).thenAnswer((_) async => ['Triphora pusilla', 'Monophorus pusillus']);
      givenSearch(
        'Triphora pusilla',
        () async => throw const TaxonNotFoundException('Triphora pusilla'),
      );
      givenSearch('Monophorus pusillus', () async => 707);

      expect(await resolver.searchTaxonId(_species(genus: 'Triphora')), 707);
      verify(allowedAncestors.requirementForSpecies(_gastropoda)).called(1);
      verify(taxonIds.resolve('Triphora pusilla', ancestry: _molluscs));
      verify(taxonIds.resolve('Monophorus pusillus', ancestry: _molluscs));
    });

    test('does not search for a species the ETL rejected, and settles it as '
        'none', () async {
      when(
        rejections.isRejected('sp1', ExternalIdProvider.inaturalist),
      ).thenAnswer((_) async => true);
      givenSearch('Triphora pusilla', () async => 1217363);

      await expectLater(
        resolver.searchTaxonId(_species(genus: 'Triphora')),
        throwsA(isA<TaxonNotFoundException>()),
      );
      verifyNever(taxonIds.resolve(any, ancestry: anyNamed('ancestry')));
    });

    test('does not search for a species without a chain up to its class, and '
        'settles it as none', () async {
      when(
        allowedAncestors.requirementForSpecies(null),
      ).thenAnswer((_) async => const INatAncestryRequirement([]));
      givenSearch('Triphora pusilla', () async => 1217363);

      await expectLater(
        resolver.searchTaxonId(_species(genus: 'Triphora', classId: null)),
        throwsA(isA<TaxonNotFoundException>()),
      );
      verifyNever(taxonIds.resolve(any, ancestry: anyNamed('ancestry')));
    });

    test('searches by name alone with a reference database that cannot say '
        'which phyla fit', () async {
      when(
        allowedAncestors.requirementForSpecies(any),
      ).thenAnswer((_) async => null);
      givenSearch('Triphora pusilla', () async => 706);

      expect(await resolver.searchTaxonId(_species(genus: 'Triphora')), 706);
      verify(taxonIds.resolve('Triphora pusilla', ancestry: null));
    });

    test('answers null when a search failed, to be retried', () async {
      givenSearch('Triphora pusilla', () async => null);

      expect(await resolver.searchTaxonId(_species(genus: 'Triphora')), isNull);
    });
  });
}
