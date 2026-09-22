/// Architecture test (ARCH-12) — what `all_tests.dart` demands of a file.
///
/// It is the single entry point CI uses to run every integration test in one
/// build, and that has two consequences a file has to respect.
///
/// It must be registered there (import + `main()` call). A file left out
/// still passes `flutter test integration_test/` locally, and silently never
/// runs in CI.
///
/// And its `setUp`/`tearDown` must sit inside a `group`. `all_tests.dart`
/// calls every file's `main()`, so a callback registered at the root of one
/// file runs before (or after) *every* test in the suite, not just its own.
/// Twenty-two files each resetting the database that way means a file's own
/// seed is wiped by the resets of every file registered after it — which is
/// invisible when the file runs alone, and is why a suite run failed at a
/// different test each time.
///
/// Run with: flutter test test/architecture/integration_test_registration_test.dart
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'arch_assertions.dart';

void main() {
  test(
    'all integration_test/*_test.dart files are registered in all_tests.dart',
    () {
      final integrationTestDir = Directory('integration_test');
      final allTestsFile = File('integration_test/all_tests.dart');
      final allTestsContent = allTestsFile.readAsStringSync();

      final testFiles =
          integrationTestDir
              .listSync()
              .whereType<File>()
              .map((f) => f.uri.pathSegments.last)
              .where((name) => name.endsWith('_test.dart'))
              .toList()
            ..sort();

      expectScanFound(testFiles.length, 15, 'integration test files');

      final violations = <String>[];

      for (final fileName in testFiles) {
        final importMatch = RegExp(
          "import '${RegExp.escape(fileName)}' as (\\w+);",
        ).firstMatch(allTestsContent);

        if (importMatch == null) {
          violations.add('$fileName: missing import in all_tests.dart');
          continue;
        }

        final alias = importMatch.group(1)!;
        final callRegex = RegExp('\\b${RegExp.escape(alias)}\\.main\\(\\);');
        if (!callRegex.hasMatch(allTestsContent)) {
          violations.add(
            '$fileName: imported as "$alias" but "$alias.main()" is never '
            'called in all_tests.dart\'s main()',
          );
        }
      }

      expect(
        violations,
        isEmpty,
        reason:
            'ARCH-12: integration_test/all_tests.dart is missing some test '
            'files.\n'
            'Add both an import and a main() call for each — see '
            'CLAUDE.md\'s testing section.\n'
            'Violations:\n  ${violations.join('\n  ')}',
      );
    },
  );

  test('integration tests scope setUp/tearDown to a group', () {
    final violations = <String>[];
    var scannedFiles = 0;
    var recognisedCallbacks = 0;

    for (final entity in Directory('integration_test').listSync()) {
      if (entity is! File) continue;
      final fileName = entity.uri.pathSegments.last;
      if (!fileName.endsWith('_test.dart')) continue;

      scannedFiles++;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (!_callbackDeclaration.hasMatch(line.trimLeft())) continue;
        recognisedCallbacks++;
        // Two spaces of indentation is main()'s own level: a callback there
        // belongs to the whole suite rather than to this file's tests.
        if (line.startsWith('  ') && !line.startsWith('   ')) {
          violations.add('$fileName:${i + 1}: ${line.trim()}');
        }
      }
    }

    expectScanFound(scannedFiles, 15, 'integration test files');
    expectScanFound(recognisedCallbacks, 15, 'setUp/tearDown callbacks');

    expect(
      violations,
      isEmpty,
      reason:
          'ARCH-12: wrap this file\'s tests in a group() and move the '
          'callback inside it.\n'
          'all_tests.dart calls every file\'s main(), so a setUp at the root '
          'of one file also runs before every other file\'s tests — '
          'resetting the database another file just seeded.\n'
          'Violations:\n  ${violations.join('\n  ')}',
    );
  });
}

/// A `setUp(`/`tearDown(`/`setUpAll(`/`tearDownAll(` registration.
final _callbackDeclaration = RegExp(r'^(setUp|tearDown)(All)?\(');
