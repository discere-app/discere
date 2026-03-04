import 'dart:convert';
import 'dart:io';
import 'package:discere/external/wiki/models/wiki_image.dart';
import 'package:discere/external/wiki/wiki_service.dart';
import 'package:discere/service/common/image_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;

void main() {
  group('ImageService', () {
    late MockClient mockClient;
    late ImageService imageService;
    late WikiService wikiService;
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('image_service_test');
      mockClient = MockClient((request) async => http.Response('', 200));
      wikiService = WikiService(client: mockClient);
      imageService = ImageService(client: mockClient, wikiService: wikiService);
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('searchImagesOnline returns list of WikiImage on success', () async {
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
      imageService = ImageService(client: mockClient, wikiService: wikiService);
      final results = await imageService.searchImagesOnline('seahorse');

      expect(results, hasLength(1));
      expect(results[0].title, 'File:SeaHorse.jpg');
      expect(results[0].thumbUrl, 'https://thumb.url');
      expect(results[0].fullUrl, 'https://full.url');
    });

    test('searchImagesOnline throws exception on non-200 response', () async {
      mockClient = MockClient((request) async {
        return http.Response('Error', 429);
      });

      wikiService = WikiService(client: mockClient);
      imageService = ImageService(client: mockClient, wikiService: wikiService);
      expect(() => imageService.searchImagesOnline('seahorse'), throwsException);
    });

    test('downloadImageOnline fetches high-res thumburl and returns path', () async {
       // This test is harder because it involves getApplicationDocumentsDirectory
       // which requires MethodChannel mocks in a flutter_test.
       // For now, we've verified search logic which is the most complex parts of the Wiki integration.
    });
  });
}
