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

    group('prune', () {
      const kept = 'https://static.inaturalist.org/photos/1/medium.jpg';
      const orphaned = 'https://static.inaturalist.org/photos/2/medium.jpg';
      const otherHost = 'https://inaturalist-open-data.s3.amazonaws.com/a.jpg';

      Future<File> cachedCopy(
        String url, {
        String storageDirectory = 'external_images',
        int size = 1,
      }) async {
        final file = File(
          await store.pathFor(url, storageDirectory: storageDirectory),
        );
        await file.parent.create(recursive: true);
        await file.writeAsBytes(List.filled(size, 1));
        return file;
      }

      Future<File> fileAt(List<String> segments) async {
        final file = File(p.joinAll([tempDir.path, ...segments]));
        await file.parent.create(recursive: true);
        await file.writeAsBytes([1]);
        return file;
      }

      test('keeps the copies of the given URLs and clears everything else, '
          'emptied host folders included', () async {
        final keptFile = await cachedCopy(kept, size: 1000);
        final orphanedFile = await cachedCopy(orphaned, size: 100);
        final partFile = File('${keptFile.path}.part');
        await partFile.writeAsBytes(List.filled(20, 1));
        final otherHostFile = await cachedCopy(otherHost, size: 3);

        final pruned = await store.prune(
          'external_images',
          keepUrls: {kept, 'https://static.inaturalist.org/photos/3/x.jpg'},
        );

        expect(pruned, (deletedFiles: 3, freedBytes: 123));
        expect(await keptFile.exists(), isTrue);
        expect(await orphanedFile.exists(), isFalse);
        expect(await partFile.exists(), isFalse);
        expect(await otherHostFile.parent.exists(), isFalse);
        expect(
          await Directory(p.join(tempDir.path, 'external_images')).exists(),
          isTrue,
        );
      });

      test('clears a folder emptied below a host folder', () async {
        await fileAt(['external_images', 'host_org', 'nested', 'stray.jpg']);

        await store.prune('external_images', keepUrls: const {});

        expect(
          await Directory(
            p.join(tempDir.path, 'external_images'),
          ).list().isEmpty,
          isTrue,
        );
      });

      test('leaves every other storage directory alone', () async {
        final reference = await cachedCopy(
          orphaned,
          storageDirectory: 'reference_images',
        );
        final cover = await fileAt(['deck_covers', 'cover_1.jpg']);
        await cachedCopy(orphaned);

        await store.prune('external_images', keepUrls: const {});

        expect(await reference.exists(), isTrue);
        expect(await cover.exists(), isTrue);
      });

      test('has nothing to clear in a storage directory that does not '
          'exist', () async {
        expect(
          await store.prune('external_images', keepUrls: {kept}),
          (deletedFiles: 0, freedBytes: 0),
        );
      });

      test('a URL to keep that cannot be named keeps nothing and does not '
          'hold up the rest', () async {
        final keptFile = await cachedCopy(kept);
        final orphanedFile = await cachedCopy(orphaned);

        final pruned = await store.prune(
          'external_images',
          keepUrls: {kept, 'https://[::1'},
        );

        expect(pruned.deletedFiles, 1);
        expect(await keptFile.exists(), isTrue);
        expect(await orphanedFile.exists(), isFalse);
      });

      test('neither follows nor deletes a link', () async {
        final outside = await fileAt(['elsewhere', 'precious.jpg']);
        final link = Link(p.join(tempDir.path, 'external_images', 'linked'));
        await link.parent.create(recursive: true);
        await link.create(outside.parent.path);

        await store.prune('external_images', keepUrls: const {});

        expect(await outside.exists(), isTrue);
        expect(await link.exists(), isTrue);
      });

      test('clears what it can when a file will not go', () async {
        final stuck = await cachedCopy(orphaned, size: 50);
        final clearable = await cachedCopy(otherHost, size: 7);
        // A folder without write permission keeps its files.
        await Process.run('chmod', ['555', stuck.parent.path]);
        addTearDown(() => Process.run('chmod', ['755', stuck.parent.path]));

        final pruned = await store.prune(
          'external_images',
          keepUrls: const {},
        );

        // The file that stayed frees nothing.
        expect(pruned, (deletedFiles: 1, freedBytes: 7));
        expect(await stuck.exists(), isTrue);
        expect(await clearable.exists(), isFalse);
      }, skip: Platform.isWindows ? 'needs POSIX permissions' : false);
    });
  });
}
