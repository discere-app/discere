import 'package:discere/catalog/repository/fts_match_term.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import 'test_utils.dart';

/// [ftsMatchTerm] has to keep a typed term parseable under the FTS4 query
/// syntax of the SQLite the app actually runs on, and that syntax differs
/// between platforms: Android's SQLite parses the standard syntax, the
/// host's sqlite3 the enhanced one (and the host-run unit tests only have
/// FTS5 at all). This test runs on a device through the real `sqflite`
/// plugin, so it is the one place that proves the rule against the
/// platform's own syntax.
void main() {
  initializeIntegrationTest();

  group('FTS match term on the device', () {
    late Database db;

    setUp(() async {
      db = await openDatabase(inMemoryDatabasePath);
      await db.execute(
        'CREATE VIRTUAL TABLE names_fts USING fts4(name, tokenize=unicode61)',
      );
      for (final name in [
        'Requins-Tigres',
        'Requins-maquereaux',
        'Requin blanc',
        'Requin bleu',
        'Truite arc-en-ciel',
        'Blau Hai',
      ]) {
        await db.insert('names_fts', {'name': name});
      }
    });

    tearDown(() async {
      await db.close();
    });

    Future<List<String>> namesMatching(String typed) async {
      final rows = await db.rawQuery(
        'SELECT name FROM names_fts WHERE names_fts MATCH ? ORDER BY name',
        ['${ftsMatchTerm(typed)}*'],
      );
      return [for (final row in rows) row['name'] as String];
    }

    testWidgets('a hyphenated name finds itself', (tester) async {
      expect(await namesMatching('Requins-Tig'), ['Requins-Tigres']);
      expect(await namesMatching('arc-en-ciel'), ['Truite arc-en-ciel']);
    });

    testWidgets('a leading hyphen does not fail the expression', (
      tester,
    ) async {
      expect(await namesMatching('-requins'), [
        'Requins-Tigres',
        'Requins-maquereaux',
      ]);
    });

    testWidgets('an unpaired quote or parenthesis does not fail the '
        'expression', (tester) async {
      expect(await namesMatching('requin "bl'), [
        'Requin blanc',
        'Requin bleu',
      ]);
      expect(await namesMatching('(requin'), [
        'Requin blanc',
        'Requin bleu',
        'Requins-Tigres',
        'Requins-maquereaux',
      ]);
    });
  });
}
