import 'package:sqflite/sqflite.dart';

import 'database_helper.dart';

class DownloadedNameSearchDocument {
  final String entityKey;
  final String entityId;
  final String entityType;
  final String scientificName;
  final String? commonNameEn;
  final String? commonNameDe;
  final String? commonNameFr;
  final String? commonNameEs;

  const DownloadedNameSearchDocument({
    required this.entityKey,
    required this.entityId,
    required this.entityType,
    required this.scientificName,
    this.commonNameEn,
    this.commonNameDe,
    this.commonNameFr,
    this.commonNameEs,
  });
}

/// Maintains a user-side search index for downloaded iNaturalist names.
///
/// The reference DB remains the primary source for built-in search. This
/// repository adds a lightweight local index for imported iNaturalist names so
/// they can participate in search without modifying the bundled reference DB.
class DownloadedNameSearchRepository {
  static const documentsTable = 'downloaded_name_search_documents';
  static const ftsTable = 'downloaded_name_search_fts';

  final Database? _injectedDb;

  DownloadedNameSearchRepository({Database? database}) : _injectedDb = database;

  Future<Database> get _database async =>
      _injectedDb ?? await DatabaseHelper.userDb;

  Future<void> upsertDocument(DownloadedNameSearchDocument document) async {
    await upsertDocuments([document]);
  }

  Future<void> upsertDocuments(
    Iterable<DownloadedNameSearchDocument> documents,
  ) async {
    final db = await _database;
    final uniqueDocuments = {
      for (final document in documents) document.entityKey: document,
    }.values.toList();

    if (uniqueDocuments.isEmpty) return;

    await db.transaction((txn) async {
      for (final document in uniqueDocuments) {
        await txn.insert(documentsTable, {
          'entity_key': document.entityKey,
          'entity_id': document.entityId,
          'entity_type': document.entityType,
          'scientific_name': document.scientificName,
          'common_name_en': document.commonNameEn,
          'common_name_de': document.commonNameDe,
          'common_name_fr': document.commonNameFr,
          'common_name_es': document.commonNameEs,
          'normalized_search_text': _normalizedSearchText(document),
        }, conflictAlgorithm: ConflictAlgorithm.replace);

        await txn.delete(
          ftsTable,
          where: 'entity_key = ?',
          whereArgs: [document.entityKey],
        );
        await txn.insert(ftsTable, {
          'entity_key': document.entityKey,
          'scientific_name': document.scientificName,
          'common_name_en': document.commonNameEn,
          'common_name_de': document.commonNameDe,
          'common_name_fr': document.commonNameFr,
          'common_name_es': document.commonNameEs,
        });
      }
    });
  }

  Future<List<Map<String, dynamic>>> searchFts(String wildcardTerm) async {
    final db = await _database;
    return db.rawQuery(
      '''
      SELECT d.*
      FROM $ftsTable f
      JOIN $documentsTable d ON d.entity_key = f.entity_key
      WHERE $ftsTable MATCH ?
    ''',
      [wildcardTerm],
    );
  }

  Future<List<Map<String, dynamic>>> searchFallback(
    String normalizedTerm,
  ) async {
    if (normalizedTerm.isEmpty) return [];

    final db = await _database;
    final prefixTerm = '$normalizedTerm%';
    final containsTerm = '%$normalizedTerm%';

    return db.query(
      documentsTable,
      where: 'normalized_search_text LIKE ? OR normalized_search_text LIKE ?',
      whereArgs: [prefixTerm, containsTerm],
      limit: 25,
    );
  }

  static String normalizeSearchText(String text) {
    const replacements = {
      'á': 'a',
      'à': 'a',
      'ä': 'a',
      'â': 'a',
      'ã': 'a',
      'å': 'a',
      'ç': 'c',
      'é': 'e',
      'è': 'e',
      'ë': 'e',
      'ê': 'e',
      'í': 'i',
      'ì': 'i',
      'ï': 'i',
      'î': 'i',
      'ñ': 'n',
      'ó': 'o',
      'ò': 'o',
      'ö': 'o',
      'ô': 'o',
      'õ': 'o',
      'ú': 'u',
      'ù': 'u',
      'ü': 'u',
      'û': 'u',
      'ý': 'y',
      'ÿ': 'y',
      'æ': 'ae',
      'œ': 'oe',
    };

    var normalized = text.toLowerCase().trim();
    replacements.forEach((source, target) {
      normalized = normalized.replaceAll(source, target);
    });
    normalized = normalized.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
    normalized = normalized.replaceAll(RegExp(r'\s+'), ' ').trim();
    return normalized;
  }

  String _normalizedSearchText(DownloadedNameSearchDocument document) {
    return normalizeSearchText(
      [
        document.scientificName,
        document.commonNameEn,
        document.commonNameDe,
        document.commonNameFr,
        document.commonNameEs,
      ].whereType<String>().join(' '),
    );
  }
}
