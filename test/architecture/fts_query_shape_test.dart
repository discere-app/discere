/// Architecture test (ARCH-14) — every reference-DB FTS lookup keeps the
/// `IN (SELECT … FROM *_fts WHERE … MATCH ?)` shape.
///
/// `search_sql.dart` reaches its FTS tables only through an `IN`-subquery,
/// never by joining the FTS table into the query that selects the entity
/// rows. That is not a style preference: with a direct join SQLite's planner
/// starts at the entity table, walks 138K+ species through
/// `idx_species_status` and probes the FTS virtual table once per row, which
/// turns a sub-300 ms search into 20–100+ seconds on a low-end device. The
/// `IN`-subquery forces FTS to be evaluated first, so only the handful of
/// rowids it returns are ever looked up.
///
/// Nothing else protects that. The two forms are semantically identical, so
/// every test stays green either way, and a direct join reads like the
/// tidier query — which is exactly how someone would "clean it up" and ship
/// an unusable search.
///
/// **What this rule does not do.** It guards the *form* of the query text,
/// not its runtime. It cannot tell a fast query from a slow one, and it will
/// not notice a performance regression from any other cause — a dropped
/// index, a widened `LIKE` fallback, a new query added next to these. Nor
/// can a timing or `EXPLAIN QUERY PLAN` test stand in for it: against the
/// small test fixture the planner picks a good plan for *both* forms, so the
/// difference only exists at real data volume, which the test suite does not
/// have. The form is the only part of this decision a test can hold onto.
///
/// Scope: queries written in Dart under `lib/`. The FTS tables created by
/// `assets/sql/` and by the ETL pipeline are schema, not lookups, and are
/// not read here.
///
/// Run with: flutter test test/architecture/fts_query_shape_test.dart
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'arch_assertions.dart';

/// An FTS table pulled into a query's `FROM`/`JOIN` list — the clause this
/// rule inspects. Case-insensitive so a differently-cased `from`/`join`
/// cannot slip through.
final _ftsClause = RegExp(
  r'\b(FROM|JOIN)\s+"?(\w*_fts)\b',
  caseSensitive: false,
);

/// Any mention of an FTS table at all, used as the vacuity floor: a scan
/// that no longer recognises an FTS table name is not checking anything.
final _ftsMention = RegExp(r'\w*_fts\b');

/// The sanctioned shape, matched against the text *preceding* an FTS
/// table's `FROM`: an `IN (SELECT` plus a column list, and nothing else in
/// between. The column-list character class is what makes this an anchor
/// rather than a loose "contains `IN (SELECT` somewhere" — an intervening
/// `FROM`, parenthesis or operator breaks the match.
final _inSubqueryPrefix = RegExp(
  r'IN\s*\(\s*SELECT\s+[\w.,\s]*$',
  caseSensitive: false,
);

/// FTS tables this rule deliberately leaves alone, with the reason.
///
/// `runtime_common_name_search_fts` lives in the *user* database over the
/// enrichment-filled runtime common-name cache — a few thousand rows a user
/// actually downloaded, not the reference DB's 138K species. The planner
/// pathology above needs a large entity table to walk, so the join form
/// there is a deliberate, safe choice rather than a violation waiting to be
/// fixed, and baselining it would say the opposite.
const _exemptFtsTables = {'runtime_common_name_search_fts'};

void main() {
  test('reference-DB FTS lookups use the IN-subquery form, never a JOIN', () {
    final violations = <String>[];
    var scannedFiles = 0;
    var recognisedMentions = 0;
    var recognisedClauses = 0;

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;

      final relativePath = entity.path.replaceAll('\\', '/');
      if (relativePath.startsWith('lib/l10n/')) continue;
      scannedFiles++;

      // The doc comments on this decision quote the forbidden form on
      // purpose; the rule is about the SQL a query actually runs.
      final code = _codeWithLineIndex(entity.readAsLinesSync());
      recognisedMentions += _ftsMention.allMatches(code.text).length;

      for (final match in _ftsClause.allMatches(code.text)) {
        final table = match.group(2)!;
        if (_exemptFtsTables.contains(table)) continue;
        recognisedClauses++;

        final keyword = match.group(1)!.toUpperCase();
        final where = '$relativePath:${code.lineAt(match.start)}';

        if (keyword == 'JOIN') {
          violations.add('$where: JOIN $table');
          continue;
        }
        final prefix = code.text.substring(0, match.start);
        if (!_inSubqueryPrefix.hasMatch(prefix)) {
          violations.add('$where: FROM $table outside an IN (SELECT …)');
        }
      }
    }

    expectScanFound(scannedFiles, 200, 'Dart files under lib/');
    expectScanFound(recognisedMentions, 12, 'FTS table names');
    expectScanFound(recognisedClauses, 9, 'reference-DB FTS FROM/JOIN clauses');

    expect(
      violations,
      isEmpty,
      reason:
          'ARCH-14: reach an FTS table only through '
          '`IN (SELECT <id> FROM <t>_fts WHERE <t>_fts MATCH ?)`, as the '
          'rest of search_sql.dart does.\n'
          "Joining the FTS table in makes SQLite's planner scan the entity "
          'table and probe FTS per row — same results, 20–100+ seconds '
          'instead of under 300 ms. Both forms pass every other test, so '
          'this is the only thing standing between the tidier-looking query '
          'and an unusable search.\n'
          'Violations:\n  ${violations.join('\n  ')}',
    );
  });
}

/// A file's code (comment lines dropped) as one whitespace-joined string,
/// with a mapping back from character offset to source line — so a
/// violation is reported where it was written even though the match ran
/// across line breaks, which every one of these queries does.
class _IndexedCode {
  final String text;
  final List<int> _starts;
  final List<int> _lines;

  const _IndexedCode(this.text, this._starts, this._lines);

  int lineAt(int offset) {
    for (var i = _starts.length - 1; i >= 0; i--) {
      if (offset >= _starts[i]) return _lines[i];
    }
    return 1;
  }
}

_IndexedCode _codeWithLineIndex(List<String> lines) {
  final buffer = StringBuffer();
  final starts = <int>[];
  final lineNumbers = <int>[];

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].trim();
    if (line.startsWith('//')) continue;
    starts.add(buffer.length);
    lineNumbers.add(i + 1);
    buffer.write(line);
    buffer.write(' ');
  }

  return _IndexedCode(buffer.toString(), starts, lineNumbers);
}
