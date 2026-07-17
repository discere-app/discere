import 'package:sqflite/sqflite.dart';

import '../model/source.dart';
import 'package:discere/shared/persistence/database_helper.dart';

class SourceRepository {
  final Database? _injectedDb;

  SourceRepository({Database? database}) : _injectedDb = database;

  Future<Database> get _database async =>
      _injectedDb ?? await DatabaseHelper.referenceDb;

  /// Alle Quellen sortiert nach display_order — für den Credits-Screen.
  Future<List<Source>> findAll() async {
    final db = await _database;
    final results = await db.query(
      'sources',
      orderBy: 'display_order ASC, name ASC',
    );
    return results.map(Source.fromMap).toList();
  }

  Future<List<({String key, String? licenseUrl})>> distinctLicenses() async {
    final db = await _database;
    final results = await db.rawQuery('''
      SELECT DISTINCT license_key, license_url
      FROM sources
      ORDER BY license_key
    ''');
    return results
        .map(
          (r) => (
            key: r['license_key'] as String,
            licenseUrl: r['license_url'] as String?,
          ),
        )
        .toList();
  }
}
