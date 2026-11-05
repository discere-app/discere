import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:discere/shared/service/host_cooldown_tracker.dart';
import 'package:discere/shared/service/image_download_outcome.dart';
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
    late int documentsDirectoryLookups;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('image_service_test');
      documentsDirectoryLookups = 0;

      const channel = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
            if (methodCall.method == 'getApplicationDocumentsDirectory') {
              documentsDirectoryLookups++;
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

    group('downloadAndSaveUrls reports', () {
      Future<ImageDownloadOutcome> outcomeOf(
        Future<http.Response> Function(http.Request request) respond, {
        String url = 'https://images.example.org/a.jpg',
      }) async {
        imageService = ImageService(
          client: MockClient(respond),
          hostCooldownTracker: hostCooldownTracker,
        );
        final outcomes = await imageService.downloadAndSaveUrls({url});
        return outcomes[url]!;
      }

      test('a saved image with its local path', () async {
        final outcome = await outcomeOf(
          (_) async => http.Response.bytes([1, 2, 3], 200),
        );

        expect(outcome, isA<ImageSaved>());
        final localPath = (outcome as ImageSaved).localPath;
        expect(await File(localPath).readAsBytes(), [1, 2, 3]);
      });

      test('a cached image as saved, without a request', () async {
        const url = 'https://images.example.org/a.jpg';
        await outcomeOf((_) async => http.Response.bytes([1], 200), url: url);

        var requests = 0;
        final outcome = await outcomeOf((_) async {
          requests++;
          return http.Response('', 503);
        }, url: url);

        expect(outcome, isA<ImageSaved>());
        expect(requests, 0);
      });

      for (final (label, respond)
          in <(String, Future<http.Response> Function(http.Request))>[
            ('a timeout', (_) async => throw TimeoutException('slow')),
            (
              'a dropped connection',
              (request) async =>
                  throw http.ClientException('reset', request.url),
            ),
            ('a 503', (_) async => http.Response('', 503)),
            ('a 429', (_) async => http.Response('', 429)),
          ]) {
        test('$label as an unreachable host', () async {
          final outcome = await outcomeOf(respond);

          expect(
            outcome,
            isA<ImageHostUnreachable>().having(
              (o) => o.host,
              'host',
              'images.example.org',
            ),
          );
        });
      }

      test('a 403 as a refusing host', () async {
        final outcome = await outcomeOf((_) async => http.Response('', 403));

        expect(
          outcome,
          isA<ImageHostRefused>().having(
            (o) => o.host,
            'host',
            'images.example.org',
          ),
        );
      });

      test('a 404 as a missing image', () async {
        final outcome = await outcomeOf((_) async => http.Response('', 404));

        expect(
          outcome,
          isA<ImageNotFound>()
              .having((o) => o.host, 'host', 'images.example.org')
              .having((o) => o.statusCode, 'statusCode', 404),
        );
      });

      test('a host skipped while cooling down as unreachable', () async {
        for (var i = 0; i < 3; i++) {
          hostCooldownTracker.recordRetryableFailure('images.example.org');
        }
        var requests = 0;
        imageService = ImageService(
          client: MockClient((_) async {
            requests++;
            return http.Response.bytes([1], 200);
          }),
          hostCooldownTracker: hostCooldownTracker,
        );

        final outcomes = await imageService.downloadAndSaveUrls({
          'https://images.example.org/a.jpg',
        }, skipIfHostCoolingDown: true);

        expect(outcomes.values.single, isA<ImageHostUnreachable>());
        expect(requests, 0);
      });

      test('a failure on this device as a local failure', () async {
        // A file where the host's folder should go makes creating it fail
        // before any request.
        final blocker = File(
          p.join(tempDir.path, 'reference_images', 'images_example_org'),
        );
        await blocker.parent.create(recursive: true);
        await blocker.create();

        final outcome = await outcomeOf(
          (_) async => http.Response.bytes([1], 200),
        );

        expect(outcome, isA<ImageLocalFailure>());
      });
    });

    group('the fallback host', () {
      const url = 'https://www.fishbase.se/images/species/Ornil_ug.jpg';
      late List<Uri> requested;

      void respondWith(Map<String, http.Response> responsesByHost) {
        requested = [];
        imageService = ImageService(
          client: MockClient((request) async {
            requested.add(request.url);
            return responsesByHost[request.url.host]!;
          }),
          hostCooldownTracker: hostCooldownTracker,
        );
      }

      test('stands in when the original host has a problem, and its copy '
          'is saved under the original URL', () async {
        respondWith({
          'www.fishbase.se': http.Response('', 503),
          'fishbase.de': http.Response.bytes([4, 2], 200),
        });

        final outcomes = await imageService.downloadAndSaveUrls({url});

        expect(
          requested.last.toString(),
          'https://fishbase.de/images/species/Ornil_ug.jpg',
        );
        final expectedPath = p.join(
          tempDir.path,
          'reference_images',
          'www_fishbase_se',
          '${md5.convert(utf8.encode(url))}.jpg',
        );
        expect(
          outcomes[url],
          isA<ImageSaved>().having(
            (o) => o.localPath,
            'localPath',
            expectedPath,
          ),
        );
        expect(await File(expectedPath).readAsBytes(), [4, 2]);
      });

      test("reports the original host's problem when it fails too", () async {
        respondWith({
          'www.fishbase.se': http.Response('', 503),
          'fishbase.de': http.Response('', 404),
        });

        final outcomes = await imageService.downloadAndSaveUrls({url});

        expect(
          outcomes[url],
          isA<ImageHostUnreachable>().having(
            (o) => o.host,
            'host',
            'www.fishbase.se',
          ),
        );
      });

      test('is not asked when the original host says the image is '
          'missing', () async {
        respondWith({
          'www.fishbase.se': http.Response('', 404),
          'fishbase.de': http.Response.bytes([1], 200),
        });

        final outcomes = await imageService.downloadAndSaveUrls({url});

        expect(outcomes[url], isA<ImageNotFound>());
        expect(requested.map((uri) => uri.host), ['www.fishbase.se']);
      });

      test('does not exist for a host without a table entry', () async {
        respondWith({'www.sealifebase.se': http.Response('', 503)});

        await imageService.downloadAndSaveUrls({
          'https://www.sealifebase.se/images/species/a.jpg',
        });

        expect(requested.map((uri) => uri.host), ['www.sealifebase.se']);
      });
    });

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

    test(
      'resolves the documents directory once per instance, not per URL',
      () async {
        final urls = {
          for (var i = 0; i < 20; i++) 'https://host/photo$i.jpg',
        };

        await imageService.resolveSavedUrlMap(
          urls,
          storageDirectory: 'external_images',
          legacyDirectories: const {'reference_images'},
        );

        // The documents directory is fixed for the process but reached over a
        // platform channel: a bulk resolve must pay for it once, not once per
        // URL per candidate directory (#229).
        expect(documentsDirectoryLookups, 1);
      },
    );

    test('retries the documents directory after a failed lookup', () async {
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
            documentsDirectoryLookups++;
            if (documentsDirectoryLookups == 1) {
              throw PlatformException(code: 'unavailable');
            }
            return tempDir.path;
          });

      await expectLater(
        imageService.resolveSavedUrlMap({'https://host/photo.jpg'}),
        throwsA(isA<PlatformException>()),
      );

      // The failure must not be what the instance remembers — it is a
      // singleton in the app, so every later image path would inherit it.
      expect(
        await imageService.resolveSavedUrlMap({'https://host/photo.jpg'}),
        isEmpty,
      );
      expect(documentsDirectoryLookups, 2);
    });
  });
}
