import 'package:discere/catalog/repository/runtime_common_name_search_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_utils.dart';

/// `runtime_common_name_search_fts` is deliberately built with fts4, not
/// fts5, for on-device Android compatibility (see UserDbSchema's own doc
/// comment — an earlier fts5 attempt failed on some real Android runtimes).
/// Host-run unit tests can't fully vouch for this: sqflite_common_ffi links
/// whatever sqlite3 build the host machine has, which varies (see
/// test/support/in_memory_user_database.dart's fts5-vs-fts4 host shim), and
/// nothing else exercises this table end-to-end. This test runs on a real
/// device/emulator through the actual `sqflite` plugin, so it's the one
/// place that actually proves fts4 create/insert/MATCH works where it
/// matters.
void main() {
  initializeIntegrationTest();

  setUp(() async {
    await resetTestState();
  });

  testWidgets(
    'runtime common-name search FTS index creates, indexes and MATCH-queries '
    'on-device',
    (tester) async {
      final repository = RuntimeCommonNameSearchRepository();

      await repository.upsertDocument(
        const RuntimeCommonNameSearchDocument(
          entityKey: 'species:fts-smoke-test',
          entityId: 'fts-smoke-test',
          entityType: 'species',
          scientificName: 'Testus fishus',
          commonNameEn: 'Zzyzx Testfish',
        ),
      );

      final results = await repository.searchFts('Zzyzx*');

      expect(results, hasLength(1));
      expect(results.single['scientific_name'], 'Testus fishus');
      expect(results.single['common_name_en'], 'Zzyzx Testfish');
    },
    timeout: integrationTestTimeout,
  );
}
