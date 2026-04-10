import 'dart:convert';
import 'dart:io';
import 'package:discere/enrichment/external/wiki_service.dart';
import 'package:discere/catalog/model/picture.dart';
import 'package:discere/shared/service/image_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ImageService', () {
    late MockClient mockClient;
    late ImageService imageService;
    late WikiService wikiService;
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('image_service_test');

      const channel = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
            if (methodCall.method == 'getApplicationDocumentsDirectory') {
              return tempDir.path;
            }
            if (methodCall.method == 'getTemporaryDirectory') {
              return tempDir.path;
            }
            return null;
          });

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
                    'thumbmime': 'image/jpeg',
                  },
                ],
              },
            },
          },
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
      expect(
        () => imageService.searchImagesOnline('seahorse'),
        throwsException,
      );
    });

    test(
      'downloadImageOnline fetches high-res thumburl and returns path',
      () async {
        mockClient = MockClient((request) async {
          if (request.url.host == 'commons.wikimedia.org') {
            final responseData = {
              'query': {
                'pages': {
                  '1': {
                    'imageinfo': [
                      {'thumburl': 'https://highres.url/test.jpg'},
                    ],
                  },
                },
              },
            };
            return http.Response(jsonEncode(responseData), 200);
          } else if (request.url.host == 'highres.url') {
            return http.Response.bytes([1, 2, 3], 200);
          }
          return http.Response('Error', 404);
        });

        wikiService = WikiService(client: mockClient);
        imageService = ImageService(
          client: mockClient,
          wikiService: wikiService,
        );

        final path = await imageService.downloadImageOnline(
          'File:Test.jpg',
          'fallback',
        );
        expect(path, isNotNull);
        final file = File(path);
        expect(await file.exists(), isTrue);
        expect(await file.readAsBytes(), [1, 2, 3]);
      },
    );

    test('saveCoverImage copies file and returns new path', () async {
      final sourceFile = File(p.join(tempDir.path, 'source.jpg'));
      await sourceFile.writeAsBytes([4, 5, 6]);

      final path = await imageService.saveCoverImage(sourceFile.path);
      expect(path, isNotNull);
      expect(path, isNot(sourceFile.path));

      final file = File(path);
      expect(await file.exists(), isTrue);
      expect(await file.readAsBytes(), [4, 5, 6]);
    });

    test('deleteImage deletes file if it exists', () async {
      final file = File(p.join(tempDir.path, 'to_delete.jpg'));
      await file.writeAsBytes([1]);
      expect(await file.exists(), isTrue);

      await imageService.deleteImage(file.path);
      expect(await file.exists(), isFalse);
    });

    test(
      'downloadAndSaveImages downloads multiple images and returns paths',
      () async {
        mockClient = MockClient((request) async {
          if (request.url.host == 'domain.com') {
            return http.Response.bytes([7, 8, 9], 200);
          }
          return http.Response('Error', 404);
        });

        imageService = ImageService(
          client: mockClient,
          wikiService: wikiService,
        );

        final urls = {
          'https://domain.com/img1.jpg',
          'https://domain.com/img2.jpg',
        };
        final paths = await imageService.downloadAndSaveImages(urls);

        expect(paths.length, 2);
        for (final path in paths) {
          expect(await File(path).exists(), isTrue);
          expect(await File(path).readAsBytes(), [7, 8, 9]);
        }
      },
    );

    test(
      'downloadAndSaveImages handles colliding filenames via hashing',
      () async {
        mockClient = MockClient((request) async {
          return http.Response.bytes([1, 2, 3], 200);
        });

        imageService = ImageService(
          client: mockClient,
          wikiService: wikiService,
        );

        final url1 = 'https://inat.org/photos/1/medium.jpg';
        final url2 = 'https://inat.org/photos/2/medium.jpg';

        final paths = await imageService.downloadAndSaveImages({url1, url2});

        expect(paths.length, 2);
        expect(
          paths[0],
          isNot(paths[1]),
          reason:
              'Filenames should be unique even if URL ends with same segment',
        );
        expect(p.basename(paths[0]), isNot('medium.jpg'));
        expect(p.basename(paths[1]), isNot('medium.jpg'));
      },
    );

    test(
      'resolveSavedPicturesMap finds legacy iNaturalist files saved as reference images',
      () async {
        const picture = Picture(
          id: 'inat1',
          species: 'sp1',
          origin: 'iNaturalist',
          url: 'https://static.inaturalist.org/photos/1/medium.jpg',
          licenseKey: 'cc-by',
          isUsable: 1,
        );
        final legacyFile = File(
          p.join(
            tempDir.path,
            'reference_images',
            'static_inaturalist_org',
            '96e08183d1c36d5c37a3c95baf49a071.jpg',
          ),
        );
        await legacyFile.parent.create(recursive: true);
        await legacyFile.writeAsBytes([1, 2, 3]);

        final paths = await imageService.resolveSavedPicturesMap([picture]);

        expect(paths[picture.url], legacyFile.path);
      },
    );
  });
}
