import 'dart:convert';
import 'package:discere/enrichment/external/wiki_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('WikiService', () {
    late MockClient mockClient;
    late WikiService wikiService;

    test('searchWikiImages returns list of WikiImage on success', () async {
      mockClient = MockClient((request) async {
        final responseData = {
          'query': {
            'pages': {
              '1': {
                'title': 'File:SeaHorse.jpg',
                'imageinfo': [
                  {
                    'thumburl': 'https://thumb.url',
                    'url': 'https://full.url',
                    'thumbmime': 'image/jpeg'
                  }
                ]
              }
            }
          }
        };
        return http.Response(jsonEncode(responseData), 200);
      });

      wikiService = WikiService(client: mockClient);
      final results = await wikiService.searchWikiImages('seahorse');

      expect(results, hasLength(1));
      expect(results[0].title, 'File:SeaHorse.jpg');
      expect(results[0].thumbUrl, 'https://thumb.url');
      expect(results[0].fullUrl, 'https://full.url');
    });

    test('searchWikiImages throws exception on non-200 response', () async {
      mockClient = MockClient((request) async {
        return http.Response('Error', 429);
      });

      wikiService = WikiService(client: mockClient);
      expect(() => wikiService.searchWikiImages('seahorse'), throwsException);
    });

    test('fetchHighResThumbUrl returns URL on success', () async {
      mockClient = MockClient((request) async {
        final responseData = {
          'query': {
            'pages': {
              '1': {
                'imageinfo': [
                  {'thumburl': 'https://highres.url'}
                ]
              }
            }
          }
        };
        return http.Response(jsonEncode(responseData), 200);
      });

      wikiService = WikiService(client: mockClient);
      final url = await wikiService.fetchHighResThumbUrl('File:SeaHorse.jpg');
      expect(url, 'https://highres.url');
    });
  });
}
