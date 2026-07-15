import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:discere/shared/persistence/database_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DatabaseHelper Versioning Test', () {
    test('database versions start at the current baseline', () {
      expect(DatabaseHelper.referenceDbVersion, 2);
      expect(DatabaseHelper.userDbVersion, 9);
    });

    test(
      'isNewerVersionAvailable returns true when no version is stored',
      () async {
        SharedPreferences.setMockInitialValues({});

        final result = await DatabaseHelper.isNewerVersionAvailable();

        expect(result, isTrue);
      },
    );

    test(
      'isNewerVersionAvailable returns false when stored version matches current',
      () async {
        SharedPreferences.setMockInitialValues({
          DatabaseHelper.prefKeyDbVersion: DatabaseHelper.referenceDbVersion,
        });

        final result = await DatabaseHelper.isNewerVersionAvailable();

        expect(result, isFalse);
      },
    );

    test(
      'isNewerVersionAvailable returns true when stored version is older',
      () async {
        SharedPreferences.setMockInitialValues({
          DatabaseHelper.prefKeyDbVersion:
              DatabaseHelper.referenceDbVersion - 1,
        });

        final result = await DatabaseHelper.isNewerVersionAvailable();

        expect(result, isTrue);
      },
    );
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
    ];

    for (final assetPath in userDbSqlAssets) {
      test('loads SQL asset: $assetPath', () async {
        final sql = await rootBundle.loadString(assetPath);

        expect(sql, isNotEmpty);
      });
    }
  });
}
