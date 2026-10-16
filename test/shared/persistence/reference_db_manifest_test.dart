import 'package:discere/shared/persistence/reference_db_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, Object?> entry(int version, {String? url}) => {
    'version': version,
    'url': url ?? 'https://example.invalid/v$version.gz',
    'sha256': 'sha-$version',
    'compressedSizeBytes': version * 100,
    'publishedAt': '2026-10-16T00:00:00Z',
  };

  ReferenceDbManifest parse(Map<String, Object?> json) =>
      ReferenceDbManifest.fromJson(json);

  /// The top level as it repeats the newest schema-1 release.
  Map<String, Object?> topLevel(int version) => {
    ...entry(version),
    'schemaVersion': 1,
  };

  group('ReferenceDbManifest', () {
    test('without schemas, the top level is the only release', () {
      final manifest = parse({
        'version': 2,
        'schemaVersion': 1,
        'url': 'https://example.invalid/v2.gz',
        'sha256': 'sha-2',
        'compressedSizeBytes': 200,
      });

      final release = manifest.newestReadable({1, 2})!;
      expect(release.version, 2);
      expect(release.schemaVersion, 1);
      expect(release.url, 'https://example.invalid/v2.gz');
      expect(release.sha256, 'sha-2');
      expect(release.compressedSizeBytes, 200);
      expect(manifest.newestReadable({2}), isNull);
    });

    test('without schemas, a missing size reads as 0', () {
      final manifest = parse({
        'version': 2,
        'schemaVersion': 1,
        'url': 'https://example.invalid/v2.gz',
        'sha256': 'sha-2',
      });

      expect(manifest.newestReadable({1})!.compressedSizeBytes, 0);
    });

    test('an entry under schemas takes its schema from its key', () {
      final manifest = parse({
        ...topLevel(2),
        'schemas': {'1': entry(2), '2': entry(3)},
      });

      final release = manifest.newestReadable({1, 2})!;
      expect(release.version, 3);
      expect(release.schemaVersion, 2);
      expect(release.url, 'https://example.invalid/v3.gz');
      expect(release.sha256, 'sha-3');
      expect(release.compressedSizeBytes, 300);
      expect(manifest.schemaVersions, {1, 2});
    });

    test('an app reading only schema 1 gets the schema-1 entry', () {
      final manifest = parse({
        ...topLevel(2),
        'schemas': {'1': entry(2), '2': entry(3)},
      });

      final release = manifest.newestReadable({1})!;
      expect(release.version, 2);
      expect(release.schemaVersion, 1);
    });

    test('the newest version wins, even over a higher schema', () {
      // A schema-1 release published after the schema-2 one.
      final manifest = parse({
        ...topLevel(4),
        'schemas': {'1': entry(4), '2': entry(3)},
      });

      final release = manifest.newestReadable({1, 2})!;
      expect(release.version, 4);
      expect(release.schemaVersion, 1);
    });

    test('of two releases with the same version, the higher schema wins', () {
      final manifest = parse({
        ...topLevel(3),
        'schemas': {
          '2': entry(3, url: 'https://example.invalid/schema-2.gz'),
          '1': entry(3, url: 'https://example.invalid/schema-1.gz'),
        },
      });

      final release = manifest.newestReadable({1, 2})!;
      expect(release.schemaVersion, 2);
      expect(release.url, 'https://example.invalid/schema-2.gz');
    });

    test('with schemas, only the entries under it count', () {
      // A top level that names a newer release than any entry is not one
      // the manifest offers beside `schemas`.
      final manifest = parse({
        ...topLevel(9),
        'schemas': {'2': entry(3)},
      });

      expect(manifest.newestReadable({1}), isNull);
      expect(manifest.newestReadable({1, 2})!.version, 3);
      expect(manifest.schemaVersions, {2});
    });

    test('offering only unsupported schemas leaves nothing to install', () {
      final manifest = parse({
        ...topLevel(2),
        'schemas': {'3': entry(4), '4': entry(5)},
      });

      expect(manifest.newestReadable({1, 2}), isNull);
      expect(manifest.schemaVersions, {3, 4});
    });

    test('ignores fields it does not know', () {
      final manifest = parse({
        ...topLevel(2),
        'minimumAppVersion': '9.9.9',
        'schemas': {
          '2': {
            ...entry(3),
            'schemaVersion': 7,
            'notes': {'de': 'irgendwas'},
          },
        },
      });

      final release = manifest.newestReadable({2})!;
      expect(release.version, 3);
      expect(release.schemaVersion, 2);
    });

    group('rejects as a format error', () {
      void expectFormatError(Map<String, Object?> json) =>
          expect(() => parse(json), throwsFormatException);

      test('a schemas key that is not an integer', () {
        expectFormatError({
          ...topLevel(2),
          'schemas': {'two': entry(3)},
        });
        expectFormatError({
          ...topLevel(2),
          'schemas': {'2.0': entry(3)},
        });
      });

      test('an entry missing a required field', () {
        for (final field in const ['version', 'url', 'sha256']) {
          expectFormatError({
            ...topLevel(2),
            'schemas': {'2': {...entry(3)}..remove(field)},
          });
        }
      });

      test('a top level missing a required field, without schemas', () {
        for (final field in const ['version', 'schemaVersion', 'url', 'sha256']) {
          expectFormatError({...topLevel(2)}..remove(field));
        }
      });

      test('a field of the wrong type', () {
        expectFormatError({
          ...topLevel(2),
          'schemas': {'2': {...entry(3), 'version': '3'}},
        });
        expectFormatError({
          ...topLevel(2),
          'schemas': {'2': {...entry(3), 'compressedSizeBytes': '300'}},
        });
      });

      test('schemas or an entry that is not an object', () {
        expectFormatError({...topLevel(2), 'schemas': [entry(3)]});
        expectFormatError({
          ...topLevel(2),
          'schemas': {'2': 'v3'},
        });
      });
    });
  });
}
