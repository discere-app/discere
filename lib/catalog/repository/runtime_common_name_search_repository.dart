import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import 'package:discere/shared/persistence/database_helper.dart';

class RuntimeCommonNameSearchDocument {
  final String entityKey;
  final String entityId;
  final String entityType;
  final String scientificName;
  final String? commonNameEn;
  final String? commonNameDe;
  final String? commonNameFr;
  final String? commonNameEs;

  const RuntimeCommonNameSearchDocument({
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

/// Maintains a user-side search index for runtime common names.
///
/// The reference DB remains the primary source for built-in search. This
/// repository projects runtime common names into a local search
/// document table plus FTS index so they become searchable immediately.
class RuntimeCommonNameSearchRepository {
  static const documentsTable = 'runtime_common_name_search_documents';
  static const ftsTable = 'runtime_common_name_search_fts';

  final Database? _injectedDb;

  RuntimeCommonNameSearchRepository({Database? database})
    : _injectedDb = database;

  Future<Database> get _database async =>
      _injectedDb ?? await DatabaseHelper.userDb;

  Future<void> upsertDocument(RuntimeCommonNameSearchDocument document) async {
    await upsertDocuments([document]);
  }

  Future<void> upsertDocuments(
    Iterable<RuntimeCommonNameSearchDocument> documents,
  ) async {
    final db = await _database;
    final uniqueDocuments = {
      for (final document in documents) document.entityKey: document,
    }.values.toList();

    if (uniqueDocuments.isEmpty) return;

    final stopwatch = Stopwatch()..start();
    _logDebug(
      'User DB write: runtime common-name search upsert start '
      '(documents=${uniqueDocuments.length})',
    );

    const chunkSize = 25;
    try {
      for (var i = 0; i < uniqueDocuments.length; i += chunkSize) {
        final end = i + chunkSize < uniqueDocuments.length
            ? i + chunkSize
            : uniqueDocuments.length;
        final chunk = uniqueDocuments.sublist(i, end);

        _logDebug(
          'User DB write: runtime common-name search upsert chunk '
          '(${i ~/ chunkSize + 1}/${(uniqueDocuments.length / chunkSize).ceil()}, '
          'size=${chunk.length})',
        );

        await db.transaction((txn) async {
          for (final document in chunk) {
            final existingDocId = await _lookupDocumentDocId(
              txn,
              entityKey: document.entityKey,
            );
            if (existingDocId != null) {
              await txn.delete(
                ftsTable,
                where: 'rowid = ?',
                whereArgs: [existingDocId],
              );
            }

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

            final docId = await _lookupDocumentDocId(
              txn,
              entityKey: document.entityKey,
            );
            if (docId == null) continue;

            await txn.insert(ftsTable, {
              'rowid': docId,
              'scientific_name': document.scientificName,
              'common_name_en': document.commonNameEn,
              'common_name_de': document.commonNameDe,
              'common_name_fr': document.commonNameFr,
              'common_name_es': document.commonNameEs,
            });
          }
        });
      }
    } finally {
      stopwatch.stop();
      _logDebug(
        'User DB write: runtime common-name search upsert done '
        '(${stopwatch.elapsedMilliseconds}ms)',
      );
    }
  }

  Future<List<Map<String, dynamic>>> searchFts(String wildcardTerm) async {
    final db = await _database;
    return db.rawQuery(
      '''
      SELECT d.*
      FROM $ftsTable f
      JOIN $documentsTable d ON d.rowid = f.rowid
      WHERE $ftsTable MATCH ?
    ''',
      [wildcardTerm],
    );
  }

  Future<int?> _lookupDocumentDocId(
    DatabaseExecutor db, {
    required String entityKey,
  }) async {
    final rows = await db.rawQuery(
      '''
      SELECT rowid
      FROM $documentsTable
      WHERE entity_key = ?
      LIMIT 1
    ''',
      [entityKey],
    );
    if (rows.isEmpty) return null;

    final rawValue = rows.first['rowid'];
    if (rawValue is int) return rawValue;
    if (rawValue is num) return rawValue.toInt();
    return null;
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

  String _normalizedSearchText(RuntimeCommonNameSearchDocument document) {
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

  void _logDebug(String message) {
    if (kDebugMode) {
      debugPrint(message);
    }
  }
}
