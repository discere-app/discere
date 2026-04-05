import 'dart:convert';

import 'package:discere/external/inaturalist/inaturalist_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('INaturalistService.fetchPhotos', () {
    INaturalistService makeService(http.Client client) =>
        INaturalistService(client: client);

    MockClient mockClient(Map<String, dynamic> body, {int statusCode = 200}) {
      return MockClient((request) async {
        return http.Response(jsonEncode(body), statusCode);
      });
    }

    test(
      'finds correct taxon ID and fetches full details for curated photos',
      () async {
        final searchBody = {
          'results': [
            {'name': 'Amphiprion ocellaris', 'id': 54321},
          ],
        };

        final detailBody = {
          'results': [
            {
              'id': 54321,
              'name': 'Amphiprion ocellaris',
              'taxon_photos': [
                {
                  'photo': {
                    'url':
                        'https://static.inaturalist.org/photos/expert/square.jpeg',
                    'license_code': 'cc-by',
                  },
                },
              ],
            },
          ],
        };

        final client = MockClient((request) async {
          if (request.url.path == '/v1/taxa/54321') {
            return http.Response(jsonEncode(detailBody), 200);
          } else if (request.url.path == '/v1/taxa') {
            return http.Response(jsonEncode(searchBody), 200);
          }
          return http.Response('', 404);
        });

        final service = INaturalistService(client: client);
        final result = await service.fetchPhotos('Amphiprion ocellaris');
        final photos = result!.photos;

        expect(photos, hasLength(1));
        expect(result.taxonId, 54321);
        expect(photos[0].url, contains('expert'));
      },
    );

    test('falls back to research and then any quality observations', () async {
      final searchBody = {
        'results': [
          {'name': 'Rare Species', 'id': 123},
        ],
      };

      final detailBody = {
        'results': [
          {'id': 123, 'name': 'Rare Species', 'taxon_photos': []},
        ],
      };

      final client = MockClient((request) async {
        if (request.url.path.contains('/v1/taxa/123')) {
          return http.Response(jsonEncode(detailBody), 200);
        } else if (request.url.path == '/v1/taxa') {
          return http.Response(jsonEncode(searchBody), 200);
        } else if (request.url.path.contains('/v1/observations')) {
          final quality = request.url.queryParameters['quality_grade'];
          final body = {
            'results': [
              {
                'observation_photos': [
                  {
                    'photo': {
                      'url':
                          'https://static.inaturalist.org/photos/$quality/square.jpeg',
                      'license_code': 'cc0',
                    },
                  },
                ],
              },
            ],
          };
          return http.Response(jsonEncode(body), 200);
        }
        return http.Response('', 404);
      });

      final service = INaturalistService(client: client);
      final result = await service.fetchPhotos('Rare Species');
      final photos = result!.photos;

      // Should have 1 from research and 1 from any = 2 total
      expect(photos, hasLength(2));
      expect(photos[0].url, contains('research'));
      expect(photos[1].url, contains('any'));
    });

    test('strictly filters out All Rights Reserved (ARR) photos', () async {
      final searchBody = {
        'results': [
          {'name': 'Match', 'id': 1},
        ],
      };
      final detailBody = {
        'results': [
          {
            'id': 1,
            'name': 'Match',
            'taxon_photos': [
              {
                'photo': {
                  'url': 'https://static.inaturalist.org/photos/1/square.jpeg',
                  'license_code': null, // ARR
                },
              },
            ],
          },
        ],
      };

      final client = MockClient((request) async {
        if (request.url.path.contains('/v1/taxa/1')) {
          return http.Response(jsonEncode(detailBody), 200);
        }
        return http.Response(jsonEncode(searchBody), 200);
      });

      final service = INaturalistService(client: client);
      final result = await service.fetchPhotos('Match');
      final photos = result?.photos ?? [];

      expect(photos, isEmpty);
    });

    test(
      'returns empty list when no taxon in first 10 results matches exactly',
      () async {
        final body = {
          'results': [
            {'name': 'Wrong Species', 'id': 999},
          ],
        };

        final service = makeService(mockClient(body));
        final result = await service.fetchPhotos('Exact Match');
        final photos = result?.photos ?? [];

        expect(photos, isEmpty);
      },
    );

    test('returns empty on network timeout', () async {
      final client = MockClient((_) async {
        throw Exception('Connection timed out');
      });

      final service = makeService(client);
      final result = await service.fetchPhotos('Any');
      final photos = result?.photos ?? [];

      expect(photos, isEmpty);
    });
  });

  group('INaturalistService.fetchCommonNames', () {
    test(
      'maps supported lexicons, sorts by position, and dedupes names',
      () async {
        final searchBody = {
          'results': [
            {'name': 'Amphiprion ocellaris', 'id': 54321},
          ],
        };
        final taxonNamesBody = [
          {'name': 'False clownfish', 'lexicon': 'English', 'position': 2},
          {'name': 'Clown anemonefish', 'lexicon': 'English', 'position': 1},
          {
            'name': '  clown   anemonefish ',
            'lexicon': 'English',
            'position': 3,
          },
          {'name': 'Poisson-clown', 'lexicon': 'French', 'position': 1},
          {
            'name': 'Pez payaso',
            'lexicon': 'Spanish',
            'place_taxon_names': [
              {'position': 4},
            ],
          },
          {'name': 'Nemo', 'lexicon': 'Italian', 'position': 1},
        ];

        final client = MockClient((request) async {
          if (request.url.host == 'api.inaturalist.org' &&
              request.url.path == '/v1/taxa') {
            return http.Response(jsonEncode(searchBody), 200);
          }
          if (request.url.host == 'www.inaturalist.org' &&
              request.url.path == '/taxon_names.json') {
            return http.Response(jsonEncode(taxonNamesBody), 200);
          }
          return http.Response('', 404);
        });

        final service = INaturalistService(client: client);
        final result = await service.fetchCommonNames('Amphiprion ocellaris');

        expect(result, isNotNull);
        expect(result!.taxonId, 54321);
        expect(result.commonNames['en'], [
          'Clown anemonefish',
          'False clownfish',
        ]);
        expect(result.commonNames['fr'], ['Poisson-clown']);
        expect(result.commonNames['es'], ['Pez payaso']);
        expect(result.commonNames.containsKey('it'), isFalse);
      },
    );
  });

  group('INatPhoto URL helpers', () {
    test('mediumUrl swaps square to medium', () async {
      final searchBody = {
        'results': [
          {'name': 'Test species', 'id': 1},
        ],
      };
      final detailBody = {
        'results': [
          {
            'id': 1,
            'name': 'Test species',
            'taxon_photos': [
              {
                'photo': {
                  'url':
                      'https://static.inaturalist.org/photos/123/square.jpeg',
                  'license_code': 'cc-by',
                },
              },
            ],
          },
        ],
      };

      final client = MockClient((request) async {
        if (request.url.path.contains('/v1/taxa/1')) {
          return http.Response(jsonEncode(detailBody), 200);
        }
        return http.Response(jsonEncode(searchBody), 200);
      });

      final service = INaturalistService(client: client);
      final result = await service.fetchPhotos('Test species');
      final photos = result!.photos;

      expect(
        photos.first.mediumUrl,
        'https://static.inaturalist.org/photos/123/medium.jpeg',
      );
    });

    test('originalUrl swaps square to original', () async {
      final searchBody = {
        'results': [
          {'name': 'Test species', 'id': 1},
        ],
      };
      final detailBody = {
        'results': [
          {
            'id': 1,
            'name': 'Test species',
            'taxon_photos': [
              {
                'photo': {
                  'url':
                      'https://static.inaturalist.org/photos/123/square.jpeg',
                  'license_code': 'cc-by',
                },
              },
            ],
          },
        ],
      };

      final client = MockClient((request) async {
        if (request.url.path.contains('/v1/taxa/1')) {
          return http.Response(jsonEncode(detailBody), 200);
        }
        return http.Response(jsonEncode(searchBody), 200);
      });

      final service = INaturalistService(client: client);
      final result = await service.fetchPhotos('Test species');
      final photos = result!.photos;

      expect(
        photos.first.originalUrl,
        'https://static.inaturalist.org/photos/123/original.jpeg',
      );
    });
  });
}
