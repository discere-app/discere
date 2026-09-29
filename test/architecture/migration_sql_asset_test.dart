/// Architecture test (ARCH-13) — migrations do not read the current schema
/// assets.
///
/// A migration describes the schema *as it was* at its own version. The
/// `assets/sql/user_db/**/create_*.sql` files describe the schema as it is
/// today. Reaching for one from a migration ties a historical step to a file
/// that keeps changing, and the coupling is invisible from either end: the
/// migration reads correct, and so does the next edit to the asset.
///
/// It breaks in both directions. Adding a column plus an index over it to an
/// asset makes an older migration create the index against a column that is
/// not there yet on an existing device (`CREATE TABLE IF NOT EXISTS` finds
/// the table and skips the column) — that is how this surfaced, taking two
/// migration tests with it. And a rebuild-and-copy migration selects a fixed
/// column list, so a column later removed from the asset breaks its
/// `INSERT`, while one later added arrives unpopulated. The reverse direction
/// bites too: an asset that only migrations still use looks like dead weight
/// to whoever tidies up the unused ones, and deleting it breaks migration
/// steps years after they were written.
///
/// So every migration spells its tables out inline, including where the
/// frozen DDL happens to be identical to today's asset — the point is that
/// the next change to that asset cannot reach it.
///
/// This rule has no baseline: the migrations were decoupled first, and it
/// went green from the start.
///
/// Run with: flutter test test/architecture/migration_sql_asset_test.dart
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'arch_assertions.dart';

/// Where the per-version migration steps live.
const _migrationDir = 'lib/shared/persistence/migration';

/// The `_create…SqlAsset` constants declared in `user_db_schema.dart`, and
/// the `_executeSqlAsset` helper that takes one. Either name in a migration
/// is the violation — the constant is how an asset is named, the helper is
/// the only thing that reads one.
final _assetReference = RegExp(r'_create\w*SqlAsset\b|_executeSqlAsset\b');

/// A raw asset path, in case a migration ever bypasses the constants.
final _assetPath = RegExp(r"'assets/sql/");

void main() {
  test('no migration reads a schema asset', () {
    final violations = <String>[];
    var scannedFiles = 0;
    var recognisedStatements = 0;

    final directory = Directory(_migrationDir);
    for (final entity in directory.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;

      final relativePath = entity.path.replaceAll('\\', '/');
      scannedFiles++;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        // The rule is about what a migration *runs*; the doc comments
        // explaining why a table is frozen name these things on purpose.
        final code = line.trimLeft();
        if (code.startsWith('//') || code.startsWith('///')) continue;
        if (line.contains('CREATE TABLE') || line.contains('CREATE INDEX')) {
          recognisedStatements++;
        }
        if (_assetReference.hasMatch(line) || _assetPath.hasMatch(line)) {
          violations.add('$relativePath:${i + 1}: ${line.trim()}');
        }
      }
    }

    expectScanFound(scannedFiles, 15, 'migration files');
    expectScanFound(
      recognisedStatements,
      15,
      'inline CREATE TABLE/INDEX statements in migrations',
    );

    expect(
      violations,
      isEmpty,
      reason:
          'ARCH-13: a migration under $_migrationDir reads a current schema '
          'asset. Spell the table out inline instead, in the shape it had at '
          "that version, with a comment saying so — see migration_v12.dart's "
          'frozen enrichment_jobs for the form.\n'
          'Violations:\n  ${violations.join('\n  ')}',
    );
  });
}
