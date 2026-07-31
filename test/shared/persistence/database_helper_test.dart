import 'package:discere/shared/persistence/database_helper.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DatabaseHelper Versioning Test', () {
    test('user database version starts at the current baseline', () {
      expect(DatabaseHelper.userDbVersion, 14);
    });
  });

  group('DatabaseHelper User DB Assets', () {
    const userDbSqlAssets = [
      'assets/sql/user_db/tables/create_decks.sql',
      'assets/sql/user_db/tables/create_flashcard_stats.sql',
      'assets/sql/user_db/tables/create_inat_photo_cache.sql',
      'assets/sql/user_db/tables/create_runtime_common_names.sql',
      'assets/sql/user_db/tables/create_runtime_common_name_search_documents.sql',
      'assets/sql/user_db/fts/create_runtime_common_name_search_fts.sql',
      'assets/sql/user_db/tables/create_external_identifier_cache.sql',
      'assets/sql/user_db/tables/create_enrichment_jobs.sql',
      'assets/sql/user_db/tables/create_enrichment_job_stages.sql',
      'assets/sql/user_db/tables/create_enrichment_species_work.sql',
      'assets/sql/user_db/tables/create_enrichment_taxonomy_work.sql',
      'assets/sql/user_db/tables/create_enrichment_species_capability_state.sql',
      'assets/sql/user_db/tables/create_enrichment_species_deck_membership.sql',
      'assets/sql/user_db/tables/create_enrichment_unresolved_names.sql',
    ];

    for (final assetPath in userDbSqlAssets) {
      test('loads SQL asset: $assetPath', () async {
        final sql = await rootBundle.loadString(assetPath);

        expect(sql, isNotEmpty);
      });
    }
  });
}
