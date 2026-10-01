/// Architecture test (ARCH-15) — every integration test sits in exactly one
/// CI shard.
///
/// `.github/workflows/flutter_ci.yml` runs the integration suite as a
/// hand-maintained matrix of shards, each listing the files its emulator
/// executes, one `flutter test` process per file. That list is the one CI
/// actually runs. `integration_test/all_tests.dart` is only the build target
/// for the pre-built APK, so a file can be perfectly registered there —
/// ARCH-12 green — and still never run anywhere, which is how three suites
/// went years without a single CI execution.
///
/// Nothing else notices. A file missing from the matrix makes no job fail,
/// produces no skipped-test count, and passes locally where `flutter test
/// integration_test/` picks files off disk rather than out of the workflow.
/// The only visible trace is the absence of a shard name in the Actions run,
/// which is exactly the kind of thing nobody reads a green pipeline for.
///
/// "Exactly one" rather than "at least one", because the opposite mistake is
/// equally silent and costs more: a file listed in two shards runs twice,
/// burning a full emulator boot and its wall-clock on a duplicate result,
/// and still reports green.
///
/// **What this rule does not do.** It guards *membership* in the matrix,
/// nothing about the test behind it. It cannot tell whether a listed file
/// passes, and it cannot tell whether it even runs: a file in a shard that
/// hangs on app start, exits before registering a test, or is skipped at
/// runtime satisfies this rule completely. Nor does it judge *which* shard a
/// file belongs to — the grouping by `lib/` slice is a convention this rule
/// has no way to read. It closes the gap between "the file exists" and "some
/// shard names it", and that is the whole of it.
///
/// The three files that have never been in any shard are held in
/// `baseline/arch-15.txt` rather than written into this file as exemptions.
/// They are debt that has to reach zero, not a justified permanent
/// exception: their state is unknown precisely because they never ran. The
/// baseline is two-way (see [expectNoNewViolations]), so assigning one to a
/// shard forces the baseline to shrink in the same commit.
///
/// Run with: flutter test test/architecture/ci_shard_coverage_test.dart
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'arch_assertions.dart';

const _workflow = '.github/workflows/flutter_ci.yml';

/// The `matrix:` key, remembered so `shard:` is only accepted beneath it.
/// Reading the whole file for shard-shaped lines would also pick up the
/// `--target=` argument of the APK pre-build step.
final _matrixKey = RegExp(r'^( *)matrix:\s*$');

/// The `shard:` key that opens the block of shard definitions.
final _shardKey = RegExp(r'^( *)shard:\s*$');

/// A shard's `- name: <slice>` header.
final _shardName = RegExp(r'^\s*-\s*name:\s*(\S+)\s*$');

/// One line of a shard's folded `files: >-` scalar. Anchored at both ends,
/// so only a line that is nothing but a path to an integration test counts.
final _shardFile = RegExp(r'^\s*integration_test/(\w+_test\.dart)\s*$');

void main() {
  test('every integration test file is listed in exactly one CI shard', () {
    final testFiles =
        Directory('integration_test')
            .listSync()
            .whereType<File>()
            .map((f) => f.uri.pathSegments.last)
            .where((name) => name.endsWith('_test.dart'))
            .toSet()
            .toList()
          ..sort();

    final matrix = _readShardMatrix(File(_workflow).readAsLinesSync());

    expectScanFound(testFiles.length, 15, 'integration test files on disk');
    expectScanFound(matrix.shards.length, 3, 'shards in the CI matrix');
    expectScanFound(matrix.shardsOf.length, 15, 'files listed in CI shards');

    final violations = <String>[];

    for (final fileName in testFiles) {
      final shards = matrix.shardsOf[fileName] ?? const <String>[];
      if (shards.isEmpty) {
        violations.add('$fileName: listed in no shard');
      } else if (shards.length > 1) {
        violations.add('$fileName: listed in ${shards.join(', ')}');
      }
    }

    for (final entry in matrix.shardsOf.entries) {
      if (testFiles.contains(entry.key)) continue;
      violations.add(
        '${entry.key}: listed in ${entry.value.join(', ')} but no such file '
        'in integration_test/',
      );
    }

    violations.sort();

    expectNoNewViolations(
      'arch-15',
      violations,
      reason:
          'ARCH-15: add the file to exactly one shard\'s `files:` list in '
          '$_workflow (the shard whose lib/ slice the test exercises), or '
          'remove the duplicate entry.\n'
          'A file in no shard never runs in CI, however well it passes '
          'locally; a file in two shards runs twice and costs an emulator '
          'boot for the second result.',
    );
  });
}

/// The shard matrix as read out of the workflow: the shard names in order,
/// and for each listed file the shards naming it.
class _ShardMatrix {
  const _ShardMatrix(this.shards, this.shardsOf);

  final List<String> shards;
  final Map<String, List<String>> shardsOf;
}

/// Reads the `matrix: shard:` block textually.
///
/// Textual rather than via a YAML parser, for the same reason
/// `import_graph.dart` reads import directives rather than running the
/// analyzer: it keeps the architecture tests free of a dependency they would
/// otherwise be the only users of, and the block is safely delimited without
/// one — the shard definitions are exactly the lines indented deeper than
/// their `shard:` key, and the first line at or above that indentation ends
/// them. What a parser would buy is tolerance for rewriting the block in
/// another YAML style; the vacuity guards turn that into a loud failure
/// instead of a silent one.
_ShardMatrix _readShardMatrix(List<String> lines) {
  final shards = <String>[];
  final shardsOf = <String, List<String>>{};
  var matrixIndent = -1;
  var blockIndent = -1;

  for (final line in lines) {
    if (blockIndent < 0) {
      final matrix = _matrixKey.firstMatch(line);
      if (matrix != null) {
        matrixIndent = matrix.group(1)!.length;
        continue;
      }
      final shard = _shardKey.firstMatch(line);
      if (shard != null && matrixIndent >= 0) {
        if (shard.group(1)!.length > matrixIndent) {
          blockIndent = shard.group(1)!.length;
        }
      }
      continue;
    }

    if (line.trim().isEmpty) continue;
    if (_indentOf(line) <= blockIndent) break;

    final name = _shardName.firstMatch(line);
    if (name != null) {
      shards.add(name.group(1)!);
      continue;
    }

    final file = _shardFile.firstMatch(line);
    if (file != null && shards.isNotEmpty) {
      shardsOf.putIfAbsent(file.group(1)!, () => <String>[]).add(shards.last);
    }
  }

  return _ShardMatrix(shards, shardsOf);
}

int _indentOf(String line) => line.length - line.trimLeft().length;
