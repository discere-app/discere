/// Architecture test (ARCH-04) — logging goes through `Logger`.
///
/// Two halves of one rule. Production code uses the structured `Logger`
/// instead of bare `debugPrint()` (the Logger itself is exempt, since
/// debugPrint is its output sink), and no class puts a switch of its own in
/// front of it.
///
/// The second half exists because `Logger` already decides what survives a
/// release build: `_shouldLog` drops `debug` and `info` unless `kDebugMode`.
/// A per-class `_enable*Logging` flag therefore controls nothing a caller
/// can observe — but it reads as though it does, and one standing at `true`
/// reads as "this class logs in release". Two switches for one decision,
/// where only the Logger's has any effect.
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
          'ARCH-04: use Logger.forType() / _log.debug() instead of '
          'debugPrint().\n'
          'Violations:\n  ${violations.join('\n  ')}',
    );
  });

  test('no class gates logging behind a flag of its own', () {
    final violations = <String>[];
    var scannedFiles = 0;
    var recognisedLogCalls = 0;

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final relativePath = entity.path.replaceAll('\\', '/');
      if (relativePath.startsWith('lib/l10n/')) continue;

      final lines = entity.readAsLinesSync();
      scannedFiles++;
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trimLeft();
        if (line.startsWith('//')) continue;
        if (_logCall.hasMatch(line)) recognisedLogCalls++;
        if (_logGateDeclaration.hasMatch(line)) {
          violations.add('$relativePath:${i + 1}: ${line.trim()}');
        }
      }
    }

    expectScanFound(scannedFiles, 200, 'Dart files under lib/');
    expectScanFound(recognisedLogCalls, 200, 'Logger calls');

    expect(
      violations,
      isEmpty,
      reason:
          'ARCH-04: Logger decides what a build logs — drop the flag and '
          'call _log.debug(...) directly.\n'
          'A debug-level call already costs nothing in release: Logger '
          'discards it unless kDebugMode. A flag in front of it only hides '
          'which switch is the real one.\n'
          'Violations:\n  ${violations.join('\n  ')}',
    );
  });
}

/// A field whose name says it turns logging on or off, e.g.
/// `static const bool _enableSearchDebugLogging = true;`.
final _logGateDeclaration = RegExp(r'\b_?enable\w*Log\w*\s*=');

/// Any call into the Logger, used as this scan's vacuity floor: a scan that
/// recognises no logging at all is not checking anything.
final _logCall = RegExp(r'\b(Logger\.|_log\.)(debug|info|warn|error)\(');
