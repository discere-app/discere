import '../model/source.dart';
import 'database_helper.dart';

class SourcesRepository {
  /// Alle Quellen sortiert nach display_order — für den Credits-Screen.
  Future<List<Source>> findAll() async {
    final db = await DatabaseHelper.referenceDb;
    final results = await db.query(
      'sources',
      orderBy: 'display_order ASC, name ASC',
    );
    return results.map(Source.fromMap).toList();
  }

  Future<List<({String key, String? licenseUrl})>> distinctLicenses() async {
    final db = await DatabaseHelper.referenceDb;
    final results = await db.rawQuery('''
      SELECT DISTINCT license_key, license_url
      FROM sources
      ORDER BY license_key
    ''');
    return results.map((r) => (
    key:        r['license_key'] as String,
    licenseUrl: r['license_url'] as String?,
    )).toList();
  }
}