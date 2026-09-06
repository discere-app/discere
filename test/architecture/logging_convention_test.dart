/// Ensures all production code uses the structured Logger class instead of bare
/// debugPrint() calls. The Logger itself is exempt since it delegates to
/// debugPrint internally.
///
/// Run with: flutter test test/architecture/logging_convention_test.dart
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'arch_assertions.dart';

void main() {
  test('production code must use Logger instead of bare debugPrint()', () {
    final libDir = Directory('lib');
    final violations = <String>[];
    var scannedFiles = 0;
    var scannedLines = 0;

    // Logger itself uses debugPrint as its output sink — that's fine.
    const allowedFiles = {'lib/shared/util/logger.dart'};

    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;

      final relativePath = entity.path.replaceAll('\\', '/');
      if (allowedFiles.any((allowed) => relativePath.endsWith(allowed))) {
        continue;
      }

      final lines = entity.readAsLinesSync();
      scannedFiles++;
      scannedLines += lines.length;
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trimLeft();
        // Skip imports and comments
        if (line.startsWith('import ') || line.startsWith('//')) continue;
        if (line.contains('debugPrint(') || line.contains('debugPrint (')) {
          violations.add('$relativePath:${i + 1}');
        }
      }
    }

    expectScanFound(scannedFiles, 200, 'Dart files under lib/');
    expectScanFound(scannedLines, 30000, 'lines of source');

    expect(
      violations,
      isEmpty,
      reason:
          'Use Logger.forType() / _log.debug() instead of debugPrint().\n'
          'Violations:\n  ${violations.join('\n  ')}',
    );
  });
}
