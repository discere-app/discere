import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/enrichment/pipeline/service/inat_taxon_resolver.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../../../mocks.mocks.dart';

Species _species({required String? genus}) => Species(
  'sp1',
  'sp1',
  'sealifebase',
  'acroporae',
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
  ),
  const [],
);

void main() {
  late MockSpeciesRepository speciesRepository;
  late INatTaxonResolver resolver;

  setUp(() {
    speciesRepository = MockSpeciesRepository();
    resolver = INatTaxonResolver(
      speciesRepository,
      MockExternalIdRepository(),
      MockExternalIdCacheRepository(),
    );
    when(
      speciesRepository.getScientificNameCandidates(
        any,
        preferredScientificName: anyNamed('preferredScientificName'),
      ),
    ).thenAnswer((_) async => const []);
  });

  test(
    'falls back to the binomial when the reference DB has no names',
    () async {
      expect(
        await resolver.scientificNameCandidates(
          _species(genus: 'Amakusaplana'),
        ),
        ['Amakusaplana acroporae'],
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
}
