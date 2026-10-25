import 'package:discere/catalog/model/classification.dart';
import 'package:discere/catalog/model/species.dart';
import 'package:discere/enrichment/media/service/local_species_image_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../../../mocks.mocks.dart';

void main() {
  // The resolved species is a copy carrying the resolved pictures; every
  // other field has to survive the copy, or a screen showing the resolved
  // species would show something else than one showing the loaded one.
  test(
    'keeps the preferred scientific name of a species without a genus',
    () async {
      final imageService = MockImageService();
      when(
        imageService.resolveSavedUrlMap(
          any,
          storageDirectory: anyNamed('storageDirectory'),
          legacyDirectories: anyNamed('legacyDirectories'),
        ),
      ).thenAnswer((_) async => {});
      final species = Species(
        'species-1',
        '1',
        'sealifebase',
        'humilis',
        {},
        Classification(null, {}, null, null, {}, null, {}, null, {}, null),
        [],
        preferredScientificName: 'Gattya humilis',
      );

      final resolved = await LocalSpeciesImageService(
        imageService,
      ).resolve(species, const [], download: false);

      expect(resolved.species.getBinomialName(), 'Gattya humilis');
    },
  );
}
