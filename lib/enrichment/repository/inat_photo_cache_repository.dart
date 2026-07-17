import 'package:discere/catalog/model/picture.dart';
import 'package:discere/shared/external/models/inat_photo.dart';
import 'package:discere/shared/persistence/database_helper.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:sqflite/sqflite.dart';

/// Persists iNaturalist photo metadata in the user database.
///
/// Each cached entry maps a species ID to a fetched iNat photo.
/// A sentinel row with `photo_url = '__empty__'` marks species that were
/// looked up but had no photos, preventing repeated API calls.
class INatPhotoCacheRepository {
  static final _log = Logger.forType(INatPhotoCacheRepository);
  static const tableName = 'inat_photo_cache';
  static const _emptySentinel = '__empty__';

  final Database? _injectedDb;

  INatPhotoCacheRepository({Database? database}) : _injectedDb = database;

  Future<Database> get _database async =>
      _injectedDb ?? await DatabaseHelper.userDb;

  /// Returns cached iNat photos for a species, or `null` if not yet fetched.
  ///
  /// An empty list means the species was fetched but had no photos (sentinel).
  Future<List<Picture>?> getCachedPhotos(String speciesId) async {
    final db = await _database;
    final rows = await db.query(
      tableName,
      where: 'species_id = ?',
      whereArgs: [speciesId],
    );

    if (rows.isEmpty) return null; // Not cached yet.

    // Check for empty sentinel.
    if (rows.length == 1 && rows.first['photo_url'] == _emptySentinel) {
      return [];
    }

    return rows.map((row) => _rowToPicture(row, speciesId)).toList();
  }

  /// Stores fetched iNat photos for a species.
  ///
  /// If [photos] is empty, a sentinel row is inserted to avoid re-fetching.
  Future<void> cachePhotos(String speciesId, List<INatPhoto> photos) async {
    final db = await _database;
    final stopwatch = Stopwatch()..start();
    _logDebug(
      'User DB write: iNat photo cache start '
      '(species=$speciesId, photos=${photos.length})',
    );
    try {
      await db.transaction((txn) async {
        // Remove old cache entries for this species.
        await txn.delete(
          tableName,
          where: 'species_id = ?',
          whereArgs: [speciesId],
        );

        if (photos.isEmpty) {
          // Insert sentinel row.
          await txn.insert(tableName, {
            'species_id': speciesId,
            'photo_url': _emptySentinel,
            'fetched_at': DateTime.now().millisecondsSinceEpoch,
          });
          return;
        }

        for (final photo in photos) {
          await txn.insert(tableName, {
            'species_id': speciesId,
            'photo_url': photo.mediumUrl,
            'thumb_url': photo.url, // iNat default URL is the square thumb
            'attribution': photo.attribution,
            'license_code': photo.licenseCode,
            'fetched_at': DateTime.now().millisecondsSinceEpoch,
          });
        }
      });
    } finally {
      stopwatch.stop();
      _logDebug(
        'User DB write: iNat photo cache done '
        '(species=$speciesId, ${stopwatch.elapsedMilliseconds}ms)',
      );
    }
  }

  /// Converts a DB row to a [Picture] compatible with the existing image pipeline.
  Picture _rowToPicture(Map<String, dynamic> row, String speciesId) {
    final licenseCode = row['license_code'] as String? ?? '';
    return Picture(
      id: 'inat_${speciesId}_${row['photo_url'].hashCode}',
      species: speciesId,
      url: row['photo_url'] as String?,
      author: row['attribution'] as String?,
      origin: 'iNaturalist',
      licenseKey: licenseCode.toUpperCase(),
      isUsable: 1,
    );
  }

  void _logDebug(String message) {
    _log.debug(message);
  }
}
