import 'package:discere/enrichment/media/service/higher_taxon_thumbnail_service.dart';
import 'package:discere/enrichment/pipeline/service/higher_taxon_id_resolver.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../../../mocks.mocks.dart';

const _entityKey = 'genus:massaria';

void main() {
  late MockHigherTaxonIdResolver taxonIdResolver;
  late MockINatPhotoApi iNatPhotos;
  late HigherTaxonThumbnailService service;

  setUp(() {
    provideDummy<HigherTaxonResolution>(const HigherTaxonAbsent());
    taxonIdResolver = MockHigherTaxonIdResolver();
    iNatPhotos = MockINatPhotoApi();
    service = HigherTaxonThumbnailService(
      taxonIdResolver: taxonIdResolver,
      iNatPhotos: iNatPhotos,
    );
  });

  test('shows the photo of the taxon whose id is known', () async {
    when(
      taxonIdResolver.knownTaxonId(_entityKey),
    ).thenAnswer((_) async => 47120);
    when(
      iNatPhotos.fetchThumbnailUrl(47120),
    ).thenAnswer((_) async => 'https://inat.test/47120/medium.jpg');

    expect(
      await service.thumbnailUrl(_entityKey),
      'https://inat.test/47120/medium.jpg',
    );
  });

  test('keeps the placeholder without a known id, rather than looking the '
      'taxon up', () async {
    when(
      taxonIdResolver.knownTaxonId(_entityKey),
    ).thenAnswer((_) async => null);

    expect(await service.thumbnailUrl(_entityKey), isNull);
    verifyNever(taxonIdResolver.resolve(any, any));
    verifyZeroInteractions(iNatPhotos);
  });

  test('keeps the placeholder when the id lookup fails', () async {
    when(
      taxonIdResolver.knownTaxonId(_entityKey),
    ).thenThrow(StateError('database closed'));

    expect(await service.thumbnailUrl(_entityKey), isNull);
    verifyZeroInteractions(iNatPhotos);
  });
}
