import 'dart:convert';

import 'package:discere/external/wikipedia/wikipedia_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('WikipediaService.getSummary', () {
    test('fetches directly in the source language when it matches the '
        'requested locale', () async {
      final requestedUris = <Uri>[];
      final client = MockClient((request) async {
        requestedUris.add(request.url);
        return http.Response(
          jsonEncode({'extract': 'A very large filter-feeding shark.'}),
          200,
        );
      });

      final service = WikipediaService(client: client);
      final summary = await service.getSummary(
        wikipediaUrl: 'https://en.wikipedia.org/wiki/Whale_shark',
        localeCode: 'en',
      );

      expect(summary?.extract, 'A very large filter-feeding shark.');
      expect(summary?.languageCode, 'en');
      expect(requestedUris, hasLength(1));
      expect(requestedUris.single.host, 'en.wikipedia.org');
      expect(
        requestedUris.single.path,
        '/api/rest_v1/page/summary/Whale_shark',
      );
    });

    test('resolves the localized title via langlinks, then fetches the '
        'localized summary', () async {
      final requestedUris = <Uri>[];
      final client = MockClient((request) async {
        requestedUris.add(request.url);
        if (request.url.path == '/w/api.php') {
          return http.Response(
            jsonEncode({
              'query': {
                'pages': [
                  {
                    'title': 'Whale shark',
                    'langlinks': [
                      {'lang': 'de', 'title': 'Walhai'},
                    ],
                  },
                ],
              },
            }),
            200,
          );
        }
        return http.Response(jsonEncode({'extract': 'Ein Walhai.'}), 200);
      });

      final service = WikipediaService(client: client);
      final summary = await service.getSummary(
        wikipediaUrl: 'https://en.wikipedia.org/wiki/Whale_shark',
        localeCode: 'de',
      );

      expect(summary?.extract, 'Ein Walhai.');
      expect(summary?.languageCode, 'de');
      expect(requestedUris, hasLength(2));
      expect(requestedUris.first.host, 'en.wikipedia.org');
      expect(requestedUris.first.queryParameters['redirects'], '1');
      expect(requestedUris.last.host, 'de.wikipedia.org');
      expect(requestedUris.last.path, '/api/rest_v1/page/summary/Walhai');
    });

    test('resolves langlinks through a scientific-name redirect page (e.g. '
        'iNaturalist-supplied "Rhincodon typus" redirecting to "Whale '
        'shark")', () async {
      final client = MockClient((request) async {
        if (request.url.path == '/w/api.php') {
          return http.Response(
            jsonEncode({
              'query': {
                'redirects': [
                  {'from': 'Rhincodon typus', 'to': 'Whale shark'},
                ],
                'pages': [
                  {
                    'title': 'Whale shark',
                    'langlinks': [
                      {'lang': 'de', 'title': 'Walhai'},
                    ],
                  },
                ],
              },
            }),
            200,
          );
        }
        return http.Response(jsonEncode({'extract': 'Ein Walhai.'}), 200);
      });

      final service = WikipediaService(client: client);
      final summary = await service.getSummary(
        wikipediaUrl: 'https://en.wikipedia.org/wiki/Rhincodon%20typus',
        localeCode: 'de',
      );

      expect(summary?.extract, 'Ein Walhai.');
      expect(summary?.languageCode, 'de');
    });

    test('falls back to the source language when no translation exists', () async {
      final client = MockClient((request) async {
        if (request.url.path == '/w/api.php') {
          return http.Response(
            jsonEncode({
              'query': {
                'pages': [
                  {'title': 'Whale shark'},
                ],
              },
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({'extract': 'A very large filter-feeding shark.'}),
          200,
        );
      });

      final service = WikipediaService(client: client);
      final summary = await service.getSummary(
        wikipediaUrl: 'https://en.wikipedia.org/wiki/Whale_shark',
        localeCode: 'de',
      );

      expect(summary?.extract, 'A very large filter-feeding shark.');
      expect(summary?.languageCode, 'en');
    });

    test('returns null for a URL that is not a Wikipedia article', () async {
      final client = MockClient((request) async {
        throw StateError('should not make a request');
      });

      final service = WikipediaService(client: client);
      final summary = await service.getSummary(
        wikipediaUrl: 'https://www.fishbase.org/summary/Rhincodon-typus',
        localeCode: 'en',
      );

      expect(summary, isNull);
    });

    test('returns null when the summary request fails', () async {
      final client = MockClient((request) async {
        return http.Response('not found', 404);
      });

      final service = WikipediaService(client: client);
      final summary = await service.getSummary(
        wikipediaUrl: 'https://en.wikipedia.org/wiki/Whale_shark',
        localeCode: 'en',
      );

      expect(summary, isNull);
    });
  });
}
