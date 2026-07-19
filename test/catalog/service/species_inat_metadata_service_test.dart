import 'package:discere/catalog/model/external_id_provider.dart';
import 'package:discere/catalog/service/species_inat_metadata_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../../mocks.mocks.dart';

void main() {
  late MockINaturalistService mockINatService;
  late MockExternalIdRepository mockExternalIdRepository;
  late MockExternalIdCacheRepository mockExternalIdCacheRepository;
  late SpeciesInatMetadataService service;

  setUp(() {
    mockINatService = MockINaturalistService();
    mockExternalIdRepository = MockExternalIdRepository();
    mockExternalIdCacheRepository = MockExternalIdCacheRepository();

    service = SpeciesInatMetadataService(
      mockINatService,
      externalIdRepository: mockExternalIdRepository,
      externalIdCacheRepository: mockExternalIdCacheRepository,
    );
  });

  test('returns the cached value without calling iNat', () async {
    when(
      mockExternalIdCacheRepository.getExternalId(
        'sp1',
        ExternalIdProvider.iucnStatus,
      ),
    ).thenAnswer((_) async => 'vu');

    final result = await service.ensureCached(
      'sp1',
      ExternalIdProvider.iucnStatus,
    );

    expect(result, 'vu');
    verifyNever(mockINatService.fetchTaxonMetadata(any));
  });

  test('returns null without calling iNat when no taxon id is known', () async {
    when(
      mockExternalIdCacheRepository.getExternalId(
        'sp1',
        ExternalIdProvider.iucnStatus,
      ),
    ).thenAnswer((_) async => null);
    when(
      mockExternalIdRepository.getExternalId(
        'sp1',
        ExternalIdProvider.inaturalist,
      ),
    ).thenAnswer((_) async => null);
    when(
      mockExternalIdCacheRepository.getExternalId(
        'sp1',
        ExternalIdProvider.inaturalist,
      ),
    ).thenAnswer((_) async => null);

    final result = await service.ensureCached(
      'sp1',
      ExternalIdProvider.iucnStatus,
    );

    expect(result, isNull);
    verifyNever(mockINatService.fetchTaxonMetadata(any));
  });

  test('backfills and persists both fields from a single taxon-detail call, '
      'using the reference-db taxon id when available', () async {
    when(
      mockExternalIdCacheRepository.getExternalId(
        'sp1',
        ExternalIdProvider.iucnStatus,
      ),
    ).thenAnswer((_) async => null);
    when(
      mockExternalIdRepository.getExternalId(
        'sp1',
        ExternalIdProvider.inaturalist,
      ),
    ).thenAnswer((_) async => '123');
    when(mockINatService.fetchTaxonMetadata(123)).thenAnswer(
      (_) async => (
        wikipediaUrl: 'https://en.wikipedia.org/wiki/Example',
        iucnStatus: 'vu',
      ),
    );

    final result = await service.ensureCached(
      'sp1',
      ExternalIdProvider.iucnStatus,
    );

    expect(result, 'vu');
    verifyNever(
      mockExternalIdCacheRepository.getExternalId(
        'sp1',
        ExternalIdProvider.inaturalist,
      ),
    );
    verify(
      mockExternalIdCacheRepository.saveExternalId(
        'sp1',
        ExternalIdProvider.wikipedia,
        'https://en.wikipedia.org/wiki/Example',
      ),
    ).called(1);
    verify(
      mockExternalIdCacheRepository.saveExternalId(
        'sp1',
        ExternalIdProvider.iucnStatus,
        'vu',
      ),
    ).called(1);
  });

  test(
    'falls back to the cached runtime taxon id when no reference id exists',
    () async {
      when(
        mockExternalIdCacheRepository.getExternalId(
          'sp1',
          ExternalIdProvider.wikipedia,
        ),
      ).thenAnswer((_) async => null);
      when(
        mockExternalIdRepository.getExternalId(
          'sp1',
          ExternalIdProvider.inaturalist,
        ),
      ).thenAnswer((_) async => null);
      when(
        mockExternalIdCacheRepository.getExternalId(
          'sp1',
          ExternalIdProvider.inaturalist,
        ),
      ).thenAnswer((_) async => '456');
      when(mockINatService.fetchTaxonMetadata(456)).thenAnswer(
        (_) async => (
          wikipediaUrl: 'https://en.wikipedia.org/wiki/Example',
          iucnStatus: null,
        ),
      );

      final result = await service.ensureCached(
        'sp1',
        ExternalIdProvider.wikipedia,
      );

      expect(result, 'https://en.wikipedia.org/wiki/Example');
      verifyNever(
        mockExternalIdCacheRepository.saveExternalId(
          'sp1',
          ExternalIdProvider.iucnStatus,
          any,
        ),
      );
    },
  );

  test('returns null when iNat has neither field on file', () async {
    when(
      mockExternalIdCacheRepository.getExternalId(
        'sp1',
        ExternalIdProvider.iucnStatus,
      ),
    ).thenAnswer((_) async => null);
    when(
      mockExternalIdRepository.getExternalId(
        'sp1',
        ExternalIdProvider.inaturalist,
      ),
    ).thenAnswer((_) async => '123');
    when(
      mockINatService.fetchTaxonMetadata(123),
    ).thenAnswer((_) async => (wikipediaUrl: null, iucnStatus: null));

    final result = await service.ensureCached(
      'sp1',
      ExternalIdProvider.iucnStatus,
    );

    expect(result, isNull);
    verifyNever(mockExternalIdCacheRepository.saveExternalId(any, any, any));
  });
}
