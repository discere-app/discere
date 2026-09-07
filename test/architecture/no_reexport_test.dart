/// Architecture test (ARCH-08) — no re-exports under `lib/`.
///
/// An `export 'other.dart';` folds another file's public surface into this
/// one, so an importer reaches a type through a file that has nothing to do
/// with it. The import graph then shows a dependency that is not the real
/// one, and the real one not at all.
///
/// In this codebase that had produced a model importing a *repository* (to
/// reach a model the repository happened to re-export) and UI importing a
/// *service* to reach model types. Both looked deliberate and both hid a
/// genuine import cycle, which only surfaced once the four re-exports were
/// removed.
///
/// A barrel file is the legitimate use of `export` this rule rejects along
/// with the rest. If one is ever wanted, add it to [_allowedFiles] with a
/// note saying what it is a barrel for — the point is that it be a decision,
/// not an accident.
///
/// Run with: flutter test test/architecture/no_reexport_test.dart
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'arch_assertions.dart';

void main() {
  test('no file under lib/ re-exports another', () {
    // No barrel files today. See the library doc before adding one.
    const allowedFiles = <String>{};

    final export = RegExp(r"^\s*export\s+'", multiLine: true);
    final violations = <String>[];
    var scannedFiles = 0;
    var scannedDirectives = 0;

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;

      final relativePath = entity.path.replaceAll('\\', '/');
      final src = entity.readAsStringSync();
      scannedFiles++;
      scannedDirectives += RegExp(
        r"^\s*(?:import|export)\s+'",
        multiLine: true,
      ).allMatches(src).length;

      if (allowedFiles.any(relativePath.endsWith)) continue;

      for (final match in export.allMatches(src)) {
        final line = '\n'.allMatches(src.substring(0, match.start)).length + 1;
        violations.add('$relativePath:$line');
      }
    }

    expectScanFound(scannedFiles, 200, 'Dart files under lib/');
    expectScanFound(scannedDirectives, 700, 'import/export directives');

    expect(
      violations,
      isEmpty,
      reason:
          'ARCH-08: re-export found. Let importers name the file that '
          'actually '
          'declares the type instead: it keeps the import graph honest, and '
          'the architecture rules built on that graph meaningful.\n'
          'Violations:\n  ${violations.join('\n  ')}',
    );
  });
}
