import 'package:discere/catalog/repository/species_repository.dart';
import 'package:discere/shared/persistence/database_helper.dart';
import 'package:sqflite/sqflite.dart';

/// The picture URLs the reference database lists for species — the URLs
/// alone, for a caller that decides which downloaded pictures to keep and
/// needs neither the pictures' details nor the species they belong to.
class ReferencePictureUrlRepository {
  /// Species ids bound per batched lookup, below SQLite's 999-variable limit.
  static const _maxIdsPerQuery = 900;

  static const _pictures = SpeciesRepository.picturesTableName;
  static const _speciesId = SpeciesRepository.columnPictureSpeciesId;

  final Database? _injectedDb;

  ReferencePictureUrlRepository({Database? database}) : _injectedDb = database;

  Future<Database> get _database async =>
      _injectedDb ?? await DatabaseHelper.referenceDb;

  /// Every picture URL of [speciesIds], usable or not: whether a picture is
  /// shown is decided elsewhere, and a URL listed here only keeps a file.
  Future<Set<String>> urlsOf(Set<String> speciesIds) async {
    if (speciesIds.isEmpty) return const {};
    final db = await _database;
    final ids = speciesIds.toList();
    final urls = <String>{};

    for (var i = 0; i < ids.length; i += _maxIdsPerQuery) {
      final chunk = ids.skip(i).take(_maxIdsPerQuery).toList();
      final rows = await db.query(
        _pictures,
        columns: const ['url'],
        where:
            '$_speciesId IN (${List.filled(chunk.length, '?').join(', ')}) '
            'AND url IS NOT NULL',
        whereArgs: chunk,
      );
      urls.addAll([for (final row in rows) row['url'] as String]);
    }
    return urls;
  }
}
