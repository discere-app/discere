/// Architecture test (ARCH-16) — a database error is tolerated only when the
/// database was closed.
///
/// One `DatabaseException` is expected in normal operation: the user
/// database closed underneath a call nobody awaited (app teardown, an
/// integration test's reset). Every other one — a constraint, schema or data
/// fault — is a real error. A bare `on DatabaseException` cannot tell the
/// two apart, so it hides the second kind behind the first.
///
/// Two halves. Only `closed_database_tolerance.dart` may catch a
/// `DatabaseException`, which is where the distinction is drawn once. And
/// its `fallingBackOnDatabaseError` — which answers a fallback for *any*
/// database error, logging the real ones — is reserved for the callers
/// listed below, each with the reason a missing answer beats a failure
/// there. Everywhere else a real error propagates.
///
/// Run with: flutter test test/architecture/database_exception_handling_test.dart
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'arch_assertions.dart';

const _toleranceFile = 'lib/shared/persistence/closed_database_tolerance.dart';

/// Callers of `fallingBackOnDatabaseError`, with why each must answer rather
/// than fail.
const _fallbackCallers = <String, String>{
  'lib/catalog/repository/search_repository.dart':
      'A search runs several branches and merges whatever they find; one '
      'branch failing — typically an FTS syntax error from what the user '
      'typed — must leave the others to answer instead of failing the '
      'search.',
  'lib/catalog/repository/inat_reference_resolver.dart':
      'Matches iNaturalist search hits back to reference rows for the same '
      'search; without a match the hit is still shown as an iNaturalist-only '
      'row.',
  'lib/learning/service/deck_source_id_backfill_service.dart':
      'The bootstrap awaits this one-time backfill before the deck update '
      'check; a failure leaves it not-done for the next start instead of '
      'cutting the remaining deferred setup short.',
};

/// A catch clause: `on DatabaseException` after a closing brace, or opening
/// a line. A comment or string that only mentions the type does not read
/// that way.
final _catchClause = RegExp(r'(^|\})\s*on\s+DatabaseException\b');

final _fallbackCall = RegExp(r'\bfallingBackOnDatabaseError\s*\(');

final _toleranceCall = RegExp(
  r'\b(runToleratingClosedDatabase|toleratingClosedDatabase)\s*\(',
);

void main() {
  test('only the closed-database tolerance catches a DatabaseException, and '
      'only listed callers fall back on one', () {
    final catchViolations = <String>[];
    final fallbackViolations = <String>[];
    final fallbackCallersSeen = <String>{};
    var scannedFiles = 0;
    var recognisedCatches = 0;
    var recognisedHelperCalls = 0;

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final relativePath = entity.path.replaceAll('\\', '/');
      final lines = entity.readAsLinesSync();
      scannedFiles++;

      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trimLeft();
        if (line.startsWith('//')) continue;
        final location = '$relativePath:${i + 1}: ${line.trim()}';

        if (_catchClause.hasMatch(line)) {
          recognisedCatches++;
          if (relativePath != _toleranceFile) catchViolations.add(location);
        }

        if (relativePath == _toleranceFile) continue;
        if (_toleranceCall.hasMatch(line)) recognisedHelperCalls++;
        if (_fallbackCall.hasMatch(line)) {
          recognisedHelperCalls++;
          fallbackCallersSeen.add(relativePath);
          if (!_fallbackCallers.containsKey(relativePath)) {
            fallbackViolations.add(location);
          }
        }
      }
    }

    expectScanFound(scannedFiles, 200, 'Dart files under lib/');
    // The tolerance file's own catches: if these stop matching, the clause
    // pattern no longer recognises a catch at all.
    expectScanFound(recognisedCatches, 2, 'DatabaseException catch clauses');
    expectScanFound(recognisedHelperCalls, 15, 'calls into the tolerance');

    expect(
      catchViolations,
      isEmpty,
      reason:
          'ARCH-16: do not catch DatabaseException directly — it hides '
          'constraint, schema and data faults behind the closed-database '
          'case.\n'
          'Wrap the call in toleratingClosedDatabase / '
          'runToleratingClosedDatabase (closed: dropped quietly; anything '
          'else propagates and reaches the uncaught-error log), or, where a '
          'missing answer is genuinely better than a failure, in '
          'fallingBackOnDatabaseError plus an entry in _fallbackCallers '
          'saying why.\n'
          'Violations:\n  ${catchViolations.join('\n  ')}',
    );
    expect(
      fallbackViolations,
      isEmpty,
      reason:
          'ARCH-16: fallingBackOnDatabaseError answers a fallback for every '
          'database error, so only the callers in _fallbackCallers may use '
          'it. Let the error propagate instead (toleratingClosedDatabase), '
          'or add the file with the reason a fallback beats a failure '
          'there.\n'
          'Violations:\n  ${fallbackViolations.join('\n  ')}',
    );
    final staleEntries = _fallbackCallers.keys
        .where((path) => !fallbackCallersSeen.contains(path))
        .toList();
    expect(
      staleEntries,
      isEmpty,
      reason:
          'ARCH-16: these _fallbackCallers entries no longer call '
          'fallingBackOnDatabaseError — remove them, so the list keeps '
          'saying where a database error is answered rather than raised.\n'
          '  ${staleEntries.join('\n  ')}',
    );
  });
}
