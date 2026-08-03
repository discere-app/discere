import 'dart:io';
import 'package:discere/shared/service/host_cooldown_tracker.dart';
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
    late HostCooldownTracker hostCooldownTracker;
    late ImageService imageService;
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
      hostCooldownTracker = HostCooldownTracker();
      imageService = ImageService(
        client: mockClient,
        hostCooldownTracker: hostCooldownTracker,
      );
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

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
          hostCooldownTracker: hostCooldownTracker,
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
          hostCooldownTracker: hostCooldownTracker,
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

    test('downloadAndSaveUrlMap keeps a successful download when another URL '
        'fails before the network call even starts', () async {
      mockClient = MockClient(
        (request) async => http.Response.bytes([1, 2, 3], 200),
      );
      imageService = ImageService(
        client: mockClient,
        hostCooldownTracker: hostCooldownTracker,
      );

      // Sabotage the subdirectory for one host by pre-creating a *file*
      // where the download expects to create a *directory*. This makes
      // subDirectory.createSync() throw before any network call — must
      // not take the other, unrelated URL's successful download down
      // with it.
      final blockedPath = File(
        p.join(tempDir.path, 'reference_images', 'blocked_com'),
      );
      await blockedPath.parent.create(recursive: true);
      await blockedPath.create();

      const okUrl = 'https://ok.com/img.jpg';
      final result = await imageService.downloadAndSaveUrlMap({
        'https://blocked.com/img.jpg',
        okUrl,
      }, storageDirectory: 'reference_images');

      expect(result.keys, [okUrl]);
      expect(await File(result[okUrl]!).exists(), isTrue);
    });

    test(
      'downloadAndSaveUrlMap with skipIfHostCoolingDown skips a cooling-down '
      'host without issuing a request',
      () async {
        var requestCount = 0;
        mockClient = MockClient((request) async {
          requestCount++;
          return http.Response.bytes([1, 2, 3], 200);
        });
        imageService = ImageService(
          client: mockClient,
          hostCooldownTracker: hostCooldownTracker,
        );

        hostCooldownTracker.recordRetryableFailure('cooling.com');
        hostCooldownTracker.recordRetryableFailure('cooling.com');
        hostCooldownTracker.recordRetryableFailure('cooling.com');
        expect(hostCooldownTracker.cooldownForHost('cooling.com'), isNotNull);

        final result = await imageService.downloadAndSaveUrlMap(
          {'https://cooling.com/img.jpg'},
          storageDirectory: 'reference_images',
          skipIfHostCoolingDown: true,
        );

        expect(result, isEmpty);
        expect(requestCount, 0);
      },
    );

    test(
      'resolveSavedUrlMap finds legacy external files saved as reference images',
      () async {
        const url = 'https://static.inaturalist.org/photos/1/medium.jpg';
        final legacyFile = File(
          p.join(
            tempDir.path,
            'reference_images',
            'static_inaturalist_org',
            'a2051c7713b105899e83df31151559fe.jpg',
          ),
        );
        await legacyFile.parent.create(recursive: true);
        await legacyFile.writeAsBytes([1, 2, 3]);

        final paths = await imageService.resolveSavedUrlMap(
          {url},
          storageDirectory: 'external_images',
          legacyDirectories: const {'reference_images'},
        );

        expect(paths[url], legacyFile.path);
      },
    );
  });
}
