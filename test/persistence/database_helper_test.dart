import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:discere/persistence/database_helper.dart';

void main() {
  group('DatabaseHelper Versioning Test', () {
    test('isNewerVersionAvailable returns true when no version is stored', () async {
      SharedPreferences.setMockInitialValues({});
      
      final result = await DatabaseHelper.isNewerVersionAvailable();
      
      expect(result, isTrue);
    });

    test('isNewerVersionAvailable returns false when stored version matches current', () async {
      SharedPreferences.setMockInitialValues({
        DatabaseHelper.prefKeyDbVersion: DatabaseHelper.referenceDbVersion,
      });
      
      final result = await DatabaseHelper.isNewerVersionAvailable();
      
      expect(result, isFalse);
    });

    test('isNewerVersionAvailable returns true when stored version is older', () async {
      SharedPreferences.setMockInitialValues({
        DatabaseHelper.prefKeyDbVersion: DatabaseHelper.referenceDbVersion - 1,
      });
      
      final result = await DatabaseHelper.isNewerVersionAvailable();
      
      expect(result, isTrue);
    });
  });
}
