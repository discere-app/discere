import 'package:discere/shared/persistence/database_helper.dart';
import 'package:discere/shared/persistence/user_db_schema.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DatabaseHelper Versioning Test', () {
    test('user database version starts at the current baseline', () {
      expect(DatabaseHelper.userDbVersion, 19);
    });
  });

  group('DatabaseHelper User DB Assets', () {
    /// Derived from the schema itself rather than restated: a hand-kept copy
    /// of this list had drifted three assets behind it. What this adds over
    /// `schema/user_db_schema_assets_test.dart` — which reads the same files
    /// from disk — is that each one loads through `rootBundle`, i.e. is
    /// actually declared in `pubspec.yaml` and ships in the bundle.
    for (final assetPath in UserDbSchema.schemaAssetPaths) {
      test('loads SQL asset: $assetPath', () async {
        final sql = await rootBundle.loadString(assetPath);

        expect(sql, isNotEmpty);
      });
    }
  });
}
