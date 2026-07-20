import 'dart:convert';

import 'package:discere/external/inaturalist/inaturalist_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const expectedTaxonSearchFields =
      'id,name,rank,preferred_common_name,matched_term';

  group('INaturalistService.searchTaxa', () {
    test('requests expanded nested taxon fields via GET override', () async {
      late Uri capturedUri;
      late String capturedMethod;
      late Map<String, String> capturedHeaders;
      late String capturedBody;
      final client = MockClient((request) async {
        capturedUri = request.url;
        capturedMethod = request.method;
        capturedHeaders = request.headers;
        capturedBody = request.body;
        return http.Response(
          jsonEncode({
            'results': [
              {
                'id': 54321,
                'name': 'Amphiprion ocellaris',
                'rank': 'species',
                'preferred_common_name': 'Clown Anemonefish',
                'matched_term': 'Amphiprion ocellaris',
                'iconic_taxon_name': 'Actinopterygii',
                'default_photo': {
                  'id': 99,
                  'url': 'https://example.com/square.jpg',
                  'medium_url': 'https://example.com/medium.jpg',
                  'license_code': 'cc-by',
                },
              },
            ],
          }),
          200,
        );
      });

      final service = INaturalistService(client: client);
      final results = await service.searchTaxa('Amphiprion ocellaris');

      expect(capturedUri.path, '/v2/taxa');
      expect(capturedMethod, 'POST');
      expect(capturedHeaders['x-http-method-override'], 'GET');
      expect(capturedHeaders['content-type'], 'application/json');
      expect(capturedUri.queryParameters['is_active'], 'true');
      expect(capturedUri.queryParametersAll['rank'], [
        'class',
        'order',
        'family',
        'genus',
        'species',
        'subspecies',
      ]);
      expect(
        jsonDecode(capturedBody),
        containsPair(
          'fields',
          containsPair('default_photo', containsPair('medium_url', true)),
        ),
      );
      expect(results.single['iconic_taxon_name'], 'Actinopterygii');
      expect(
        results.single['default_photo_medium_url'],
        'https://example.com/medium.jpg',
      );
    });
  });

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
        late Uri searchUri;
        late String detailMethod;
        late Map<String, String> detailHeaders;
        late String detailRequestBody;
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
          if (request.url.path == '/v2/taxa/54321') {
            detailMethod = request.method;
            detailHeaders = request.headers;
            detailRequestBody = request.body;
            return http.Response(jsonEncode(detailBody), 200);
          } else if (request.url.path == '/v2/taxa') {
            searchUri = request.url;
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
        expect(searchUri.queryParameters['fields'], expectedTaxonSearchFields);
        expect(detailMethod, 'POST');
        expect(detailHeaders['x-http-method-override'], 'GET');
        expect(
          jsonDecode(detailRequestBody),
          containsPair(
            'fields',
            containsPair(
              'taxon_photos',
              containsPair('photo', containsPair('license_code', true)),
            ),
          ),
        );
      },
    );

    test('exposes the taxon Wikipedia URL from the detail response', () async {
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
            'taxon_photos': [],
            'wikipedia_url': 'https://en.wikipedia.org/wiki/Clownfish',
          },
        ],
      };
      final client = MockClient((request) async {
        if (request.url.path == '/v2/taxa/54321') {
          return http.Response(jsonEncode(detailBody), 200);
        } else if (request.url.path == '/v2/taxa') {
          return http.Response(jsonEncode(searchBody), 200);
        }
        return http.Response('', 404);
      });

      final service = INaturalistService(client: client);
      final result = await service.fetchPhotos('Amphiprion ocellaris');

      expect(result!.wikipediaUrl, 'https://en.wikipedia.org/wiki/Clownfish');
    });

    test(
      'returns a null wikipedia URL when iNaturalist has none on file',
      () async {
        final searchBody = {
          'results': [
            {'name': 'Amphiprion ocellaris', 'id': 54321},
          ],
        };
        final detailBody = {
          'results': [
            {'id': 54321, 'name': 'Amphiprion ocellaris', 'taxon_photos': []},
          ],
        };
        final client = MockClient((request) async {
          if (request.url.path == '/v2/taxa/54321') {
            return http.Response(jsonEncode(detailBody), 200);
          } else if (request.url.path == '/v2/taxa') {
            return http.Response(jsonEncode(searchBody), 200);
          }
          return http.Response('', 404);
        });

        final service = INaturalistService(client: client);
        final result = await service.fetchPhotos('Amphiprion ocellaris');

        expect(result!.wikipediaUrl, isNull);
      },
    );

    test('exposes the IUCN status from the detail response when the authority '
        'is the IUCN Red List', () async {
      final searchBody = {
        'results': [
          {'name': 'Rhincodon typus', 'id': 52188},
        ],
      };
      final detailBody = {
        'results': [
          {
            'id': 52188,
            'name': 'Rhincodon typus',
            'taxon_photos': [],
            'conservation_status': {
              'status': 'en',
              'status_name': 'endangered',
              'authority': 'IUCN Red List',
            },
          },
        ],
      };
      final client = MockClient((request) async {
        if (request.url.path == '/v2/taxa/52188') {
          return http.Response(jsonEncode(detailBody), 200);
        } else if (request.url.path == '/v2/taxa') {
          return http.Response(jsonEncode(searchBody), 200);
        }
        return http.Response('', 404);
      });

      final service = INaturalistService(client: client);
      final result = await service.fetchPhotos('Rhincodon typus');

      expect(result!.iucnStatus, 'en');
    });

    test('ignores a conservation status from a non-IUCN authority', () async {
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
            'taxon_photos': [],
            'conservation_status': {
              'status': 'sc',
              'status_name': 'special concern',
              'authority': 'NatureServe',
            },
          },
        ],
      };
      final client = MockClient((request) async {
        if (request.url.path == '/v2/taxa/54321') {
          return http.Response(jsonEncode(detailBody), 200);
        } else if (request.url.path == '/v2/taxa') {
          return http.Response(jsonEncode(searchBody), 200);
        }
        return http.Response('', 404);
      });

      final service = INaturalistService(client: client);
      final result = await service.fetchPhotos('Amphiprion ocellaris');

      expect(result!.iucnStatus, isNull);
    });

    test(
      'falls back to research and then any quality observations when allowTier3Fallback is true',
      () async {
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
          if (request.url.path.contains('/v2/taxa/123')) {
            return http.Response(jsonEncode(detailBody), 200);
          } else if (request.url.path == '/v2/taxa') {
            return http.Response(jsonEncode(searchBody), 200);
          } else if (request.url.path.contains('/v2/observations')) {
            final quality =
                request.url.queryParametersAll['quality_grade']?.single ??
                'unfiltered';
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
        final result = await service.fetchPhotos(
          'Rare Species',
          allowTier3Fallback: true,
        );
        final photos = result!.photos;

        // Should have 1 from research and 1 from the unfiltered fallback = 2 total
        expect(photos, hasLength(2));
        expect(photos[0].url, contains('research'));
        expect(photos[1].url, contains('unfiltered'));
      },
    );

    test(
      'stops after research observations when allowTier3Fallback is false',
      () async {
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

        var observationCallCount = 0;
        final client = MockClient((request) async {
          if (request.url.path.contains('/v2/taxa/123')) {
            return http.Response(jsonEncode(detailBody), 200);
          } else if (request.url.path == '/v2/taxa') {
            return http.Response(jsonEncode(searchBody), 200);
          } else if (request.url.path.contains('/v2/observations')) {
            observationCallCount++;
            final quality =
                request.url.queryParametersAll['quality_grade']?.single ??
                'unfiltered';
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

        expect(observationCallCount, 1);
        expect(photos, hasLength(1));
        expect(photos[0].url, contains('research'));
      },
    );

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
        if (request.url.path.contains('/v2/taxa/1')) {
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

    test(
      'throws TaxonNotFoundException when the taxon search confirms no match '
      'exists, distinct from a transient failure',
      () async {
        final client = MockClient((_) async {
          return http.Response(jsonEncode({'results': []}), 200);
        });

        final service = INaturalistService(client: client);

        expect(
          () => service.fetchPhotos('Nonexistent species'),
          throwsA(isA<TaxonNotFoundException>()),
        );
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

    test(
      'returns null on retryable photo-fetch failures so callers do not cache empty sentinels',
      () async {
        final searchBody = {
          'results': [
            {'name': 'Retry Species', 'id': 321},
          ],
        };

        final client = MockClient((request) async {
          if (request.url.path == '/v2/taxa') {
            return http.Response(jsonEncode(searchBody), 200);
          }
          if (request.url.path == '/v2/taxa/321') {
            return http.Response('', 429);
          }
          if (request.url.path == '/v2/observations') {
            return http.Response('', 429);
          }
          return http.Response('', 404);
        });

        final service = INaturalistService(client: client);
        final result = await service.fetchPhotos('Retry Species');

        expect(result, isNull);
      },
    );
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
              request.url.path == '/v2/taxa') {
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
        expect(result.commonNames['en']?.map((name) => name.name).toList(), [
          'Clown anemonefish',
          'False clownfish',
        ]);
        expect(
          result.commonNames['en']?.map((name) => name.position).toList(),
          [1, 2],
        );
        expect(result.commonNames['fr']?.map((name) => name.name).toList(), [
          'Poisson-clown',
        ]);
        expect(result.commonNames['es']?.map((name) => name.name).toList(), [
          'Pez payaso',
        ]);
        expect(result.commonNames['es']?.single.places, isEmpty);
        expect(result.commonNames.containsKey('it'), isFalse);
      },
    );

    test(
      'reuses a successful taxon lookup across photo and common-name requests',
      () async {
        var taxaSearchCount = 0;
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
        final taxonNamesBody = [
          {'name': 'Clown anemonefish', 'lexicon': 'English', 'position': 1},
        ];

        final client = MockClient((request) async {
          if (request.url.host == 'api.inaturalist.org' &&
              request.url.path == '/v2/taxa') {
            taxaSearchCount++;
            return http.Response(jsonEncode(searchBody), 200);
          }
          if (request.url.host == 'api.inaturalist.org' &&
              request.url.path == '/v2/taxa/54321') {
            return http.Response(jsonEncode(detailBody), 200);
          }
          if (request.url.host == 'api.inaturalist.org' &&
              request.url.path == '/v2/observations') {
            return http.Response(jsonEncode({'results': []}), 200);
          }
          if (request.url.host == 'www.inaturalist.org' &&
              request.url.path == '/taxon_names.json') {
            return http.Response(jsonEncode(taxonNamesBody), 200);
          }
          return http.Response('', 404);
        });

        final service = INaturalistService(client: client);
        final photos = await service.fetchPhotos('Amphiprion ocellaris');
        final commonNames = await service.fetchCommonNames(
          'Amphiprion ocellaris',
        );

        expect(photos, isNotNull);
        expect(commonNames, isNotNull);
        expect(taxaSearchCount, 1);
      },
    );

    test(
      'throws TaxonNotFoundException when the taxon search confirms no match '
      'exists, distinct from a transient failure',
      () async {
        final client = MockClient((_) async {
          return http.Response(jsonEncode({'results': []}), 200);
        });

        final service = INaturalistService(client: client);

        expect(
          () => service.fetchCommonNames('Nonexistent species'),
          throwsA(isA<TaxonNotFoundException>()),
        );
      },
    );

    test('does not memoize failed taxon lookups', () async {
      var taxaSearchCount = 0;
      final client = MockClient((request) async {
        if (request.url.host == 'api.inaturalist.org' &&
            request.url.path == '/v2/taxa') {
          taxaSearchCount++;
          return http.Response('', 429);
        }
        return http.Response('', 404);
      });

      final service = INaturalistService(client: client);
      final first = await service.fetchCommonNames('Retry species');
      final second = await service.fetchCommonNames('Retry species');

      expect(first, isNull);
      expect(second, isNull);
      expect(taxaSearchCount, 2);
    });
  });

  group('INaturalistService.fetchThumbnailUrl', () {
    test('returns the first curated medium thumbnail', () async {
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
        if (request.url.path == '/v2/taxa/54321') {
          return http.Response(jsonEncode(detailBody), 200);
        }
        if (request.url.path == '/v2/taxa') {
          return http.Response(jsonEncode(searchBody), 200);
        }
        return http.Response('', 404);
      });

      final service = INaturalistService(client: client);
      final result = await service.fetchThumbnailUrl('Amphiprion ocellaris');

      expect(result, isNotNull);
      expect(result, contains('/medium.'));
    });
  });

  group('INaturalistService.prefetchTaxonDetails', () {
    test('loads multiple taxon details through the batch endpoint', () async {
      final requestedPaths = <String>[];
      final client = MockClient((request) async {
        requestedPaths.add(request.url.path);
        if (request.url.path == '/v2/taxa/1,2') {
          return http.Response(
            jsonEncode({
              'results': [
                {
                  'id': 1,
                  'name': 'Specius alpha',
                  'taxon_photos': [
                    {
                      'photo': {
                        'url':
                            'https://static.inaturalist.org/photos/1/square.jpeg',
                        'license_code': 'cc-by',
                      },
                    },
                  ],
                },
                {
                  'id': 2,
                  'name': 'Specius beta',
                  'taxon_photos': [
                    {
                      'photo': {
                        'url':
                            'https://static.inaturalist.org/photos/2/square.jpeg',
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
        if (request.url.path == '/v2/observations') {
          return http.Response(jsonEncode({'results': []}), 200);
        }
        return http.Response('', 404);
      });

      final service = INaturalistService(client: client);
      await service.prefetchTaxonDetails([1, 2]);

      final alpha = await service.fetchPhotos('Specius alpha', taxonId: 1);
      final beta = await service.fetchPhotos('Specius beta', taxonId: 2);

      expect(alpha?.photos.single.url, contains('/photos/1/'));
      expect(beta?.photos.single.url, contains('/photos/2/'));
      expect(
        requestedPaths.where((path) => path == '/v2/taxa/1,2'),
        hasLength(1),
      );
      expect(requestedPaths, isNot(contains('/v2/taxa/1')));
      expect(requestedPaths, isNot(contains('/v2/taxa/2')));
    });
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
        if (request.url.path.contains('/v2/taxa/1')) {
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
        if (request.url.path.contains('/v2/taxa/1')) {
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
