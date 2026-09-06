/// Shared assertions for the scanner-style architecture tests.
///
/// Every test under `test/architecture/` follows the same shape: walk the
/// source tree, collect violations, assert the list is empty. The two
/// assertions here cover the failure modes that shape has on its own.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards against a scan that quietly stopped seeing anything.
///
/// `expect(violations, isEmpty)` also passes when the scan found nothing at
/// all — a moved directory, a renamed file suffix or a pattern that stopped
/// matching leaves the test green while it measures nothing, and the
/// convention silently stops being enforced.
///
/// Every scanner therefore states a floor for both what it read and what it
/// recognised: reading 290 files and recognising zero candidates is as
/// broken as reading none. Floors are deliberately coarse — they exist to
/// catch "the scan runs empty", not to track the codebase size. A rule that
/// wants exact numbers keeps its own baseline (see [expectNoNewViolations]).
void expectScanFound(int actual, int minimum, String what) {
  expect(
    actual,
    greaterThanOrEqualTo(minimum),
    reason:
        'Vacuity guard: the scan found $actual $what, expected at least '
        '$minimum.\n'
        'This is NOT a convention violation — the scan itself stopped seeing '
        'things, so the rule in this file is no longer being checked. Fix '
        'the scan (moved directory? renamed suffix? pattern that no longer '
        'matches?), or lower the floor deliberately if the codebase really '
        'shrank that far.',
  );
}

/// Directory holding one baseline file per ratcheted rule.
const _baselineDir = 'test/architecture/baseline';

/// Set to any non-empty value to rewrite baselines instead of asserting
/// against them: `UPDATE_ARCH_BASELINE=1 flutter test test/architecture/`.
const _updateEnvVar = 'UPDATE_ARCH_BASELINE';

/// Asserts [violations] against a stored baseline, in both directions.
///
/// A rule that today has known violations can still be introduced: its
/// current violations are frozen, and only *new* ones fail. What makes this
/// a ratchet rather than a permanent exemption list is the second direction
/// — a baseline entry that is no longer violated also fails, with a request
/// to shrink the file. Without that, a list written once only ever grows
/// stale, and the rule ends up documenting the past instead of guarding the
/// present.
///
/// [reason] explains the rule itself and is shown when new violations
/// appear; it should say how to fix one, not restate the rule's name.
///
/// [storeDir] overrides where baselines live; it exists so this function can
/// be tested against a temporary directory without touching the real store.
void expectNoNewViolations(
  String ruleId,
  List<String> violations, {
  required String reason,
  String storeDir = _baselineDir,
}) {
  final file = File('$storeDir/$ruleId.txt');

  if (Platform.environment[_updateEnvVar]?.isNotEmpty ?? false) {
    if (violations.isEmpty) {
      if (file.existsSync()) file.deleteSync();
      return;
    }
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('${violations.join('\n')}\n');
    return;
  }

  final baseline = file.existsSync()
      ? file
            .readAsLinesSync()
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty)
            .toSet()
      : <String>{};
  final current = violations.toSet();

  final added = current.difference(baseline).toList()..sort();
  expect(
    added,
    isEmpty,
    reason:
        '$reason\n\n'
        'New violations of "$ruleId" (not in $storeDir/$ruleId.txt):\n'
        '  ${added.join('\n  ')}',
  );

  final fixed = baseline.difference(current).toList()..sort();
  expect(
    fixed,
    isEmpty,
    reason:
        'The baseline for "$ruleId" is now too generous — these entries are '
        'no longer violated:\n'
        '  ${fixed.join('\n  ')}\n\n'
        'Shrink the baseline so it keeps holding the line at what is left:\n'
        '  $_updateEnvVar=1 flutter test test/architecture/\n'
        'Then commit $storeDir/$ruleId.txt alongside the fix.',
  );
}
