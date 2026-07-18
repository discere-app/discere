/// Ensures every integration_test/*_test.dart file is wired into
/// all_tests.dart (import + main() call) — the single entry point CI uses to
/// run all integration tests in one build. A file left out here still passes
/// `flutter test integration_test/` locally but silently never runs in CI.
///
/// Run with: flutter test test/architecture/integration_test_registration_test.dart
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('all integration_test/*_test.dart files are registered in all_tests.dart', () {
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
          'integration_test/all_tests.dart is missing some test files.\n'
          'Add both an import and a main() call for each — see '
          'CLAUDE.md\'s testing section.\n'
          'Violations:\n  ${violations.join('\n  ')}',
    );
  });
}
