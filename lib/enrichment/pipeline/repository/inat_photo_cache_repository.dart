import 'package:discere/catalog/model/picture.dart';
import 'package:discere/external/inaturalist/models/inat_photo.dart';
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

  /// Species ids bound per batched lookup, below SQLite's 999-variable limit.
  static const _maxIdsPerQuery = 900;

  final Database? _injectedDb;

  INatPhotoCacheRepository({Database? database}) : _injectedDb = database;

  Future<Database> get _database async =>
      _injectedDb ?? await DatabaseHelper.userDb;

  /// Returns cached iNat photos for a species, or `null` if not yet fetched.
  ///
  /// An empty list means the species was fetched but had no photos (sentinel).
  Future<List<Picture>?> getCachedPhotos(String speciesId) async {
    final cached = await getCachedPhotosForSpecies({speciesId});
    return cached[speciesId];
  }

  /// Cached iNat photos for several species in one query, keyed by species id.
  ///
  /// A species missing from the result has not been fetched yet; one mapped to
  /// an empty list was fetched and had no photos (sentinel) — the same
  /// distinction [getCachedPhotos] draws between `null` and `[]`, kept per
  /// species. Callers resolving a whole deck use this so the lookup costs one
  /// query rather than one per card.
  Future<Map<String, List<Picture>>> getCachedPhotosForSpecies(
    Set<String> speciesIds,
  ) async {
    if (speciesIds.isEmpty) return const {};
    final db = await _database;
    final ids = speciesIds.toList();
    final rowsBySpeciesId = <String, List<Map<String, Object?>>>{};

    for (var i = 0; i < ids.length; i += _maxIdsPerQuery) {
      final chunk = ids.skip(i).take(_maxIdsPerQuery).toList();
      final rows = await db.query(
        tableName,
        where: 'species_id IN (${List.filled(chunk.length, '?').join(', ')})',
        whereArgs: chunk,
      );
      for (final row in rows) {
        (rowsBySpeciesId[row['species_id'] as String] ??= []).add(row);
      }
    }

    return {
      for (final entry in rowsBySpeciesId.entries)
        entry.key: _picturesFromRows(entry.key, entry.value),
    };
  }

  List<Picture> _picturesFromRows(
    String speciesId,
    List<Map<String, Object?>> rows,
  ) {
    if (rows.length == 1 && rows.first['photo_url'] == _emptySentinel) {
      return const [];
    }
    return rows.map((row) => Picture.fromINatCacheRow(row, speciesId)).toList();
  }

  /// Stores fetched iNat photos for a species.
  ///
  /// If [photos] is empty, a sentinel row is inserted to avoid re-fetching.
  Future<void> cachePhotos(String speciesId, List<INatPhoto> photos) async {
    final db = await _database;
    final stopwatch = Stopwatch()..start();
    _log.debug(
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
      _log.debug(
        'User DB write: iNat photo cache done '
        '(species=$speciesId, ${stopwatch.elapsedMilliseconds}ms)',
      );
    }
  }

}
