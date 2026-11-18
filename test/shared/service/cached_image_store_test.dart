import 'dart:io';

import 'package:discere/shared/service/cached_image_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');

  group('CachedImageStore', () {
    late Directory tempDir;
    late int documentsDirectoryLookups;
    late CachedImageStore store;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('cached_image_store');
      documentsDirectoryLookups = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProvider, (call) async {
            documentsDirectoryLookups++;
            return tempDir.path;
          });
      store = CachedImageStore();
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProvider, null);
      await tempDir.delete(recursive: true);
    });

    group('pathFor', () {
      test(
        'files a URL under its host, named by its hash and extension',
        () async {
          expect(
            await store.pathFor(
              'https://static.inaturalist.org/photos/1/medium.jpg',
              storageDirectory: 'external_images',
            ),
            p.join(
              tempDir.path,
              'external_images',
              'static_inaturalist_org',
              'a2051c7713b105899e83df31151559fe.jpg',
            ),
          );
        },
      );

      test(
        'falls back to .jpg for a URL whose path has no extension',
        () async {
          final path = await store.pathFor(
            'https://images.example.org/photo',
            storageDirectory: 'reference_images',
          );

          expect(p.extension(path), '.jpg');
          expect(p.basename(p.dirname(path)), 'images_example_org');
        },
      );
    });

    group('existingPathFor', () {
      const url = 'https://images.example.org/a.png';

      Future<File> saveIn(String storageDirectory) async {
        final file = File(
          await store.pathFor(url, storageDirectory: storageDirectory),
        );
        await file.parent.create(recursive: true);
        await file.writeAsBytes([1]);
        return file;
      }

      test('prefers the storage directory over a legacy one', () async {
        await saveIn('reference_images');
        final current = await saveIn('external_images');

        expect(
          await store.existingPathFor(
            url,
            storageDirectory: 'external_images',
            legacyDirectories: const {'reference_images'},
          ),
          current.path,
        );
      });

      test('looks in a legacy directory only when told to', () async {
        await saveIn('reference_images');

        expect(
          await store.existingPathFor(url, storageDirectory: 'external_images'),
          isNull,
        );
      });
    });

    test(
      'resolves the documents directory once per instance, not per URL',
      () async {
        for (var i = 0; i < 20; i++) {
          await store.existingPathFor(
            'https://host/photo$i.jpg',
            storageDirectory: 'external_images',
            legacyDirectories: const {'reference_images'},
          );
        }

        // The documents directory is fixed for the process but reached over a
        // platform channel: a bulk resolve must pay for it once, not once per
        // URL per candidate directory (#229).
        expect(documentsDirectoryLookups, 1);
      },
    );

    test('retries the documents directory after a failed lookup', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProvider, (call) async {
            documentsDirectoryLookups++;
            if (documentsDirectoryLookups == 1) {
              throw PlatformException(code: 'unavailable');
            }
            return tempDir.path;
          });

      await expectLater(
        store.documentsDirectory(),
        throwsA(isA<PlatformException>()),
      );

      // The failure must not be what the instance remembers — the app holds
      // one store, so every later image path would inherit it.
      expect((await store.documentsDirectory()).path, tempDir.path);
      expect(documentsDirectoryLookups, 2);
    });
  });
}
