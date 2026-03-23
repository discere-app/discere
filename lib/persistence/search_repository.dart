import '../model/search/search_result.dart';
import 'package:sqflite/sqflite.dart';

import '../model/language.dart';
import 'database_helper.dart';

class SearchRepository {
  final Database? _injectedDb;

  SearchRepository({Database? database}) : _injectedDb = database;

  Future<Database> get _database async => _injectedDb ?? await DatabaseHelper.referenceDb;

  Future<List<SearchResult>> searchAll(String term) async {
    var wildcardTerm = '$term*';
    final db = await _database;
    final results = await db.rawQuery('''
 
      SELECT id, name, common_name_en, common_name_de, common_name_fr, common_name_es, 'species' AS entity_type, external_source, external_id
      FROM species_fts
      WHERE species_fts MATCH ?

      UNION ALL

      SELECT id, name, NULL AS common_name_en, NULL AS common_name_de, NULL AS common_name_fr, NULL AS common_name_es, 'genera' AS entity_type, NULL as external_source, NULL as external_id
      FROM genera_fts
      WHERE genera_fts MATCH ?

      UNION ALL

      SELECT id, name, common_name_en, common_name_de, common_name_fr, common_name_es, 'families' AS entity_type, NULL as external_source, NULL as external_id
      FROM families_fts
      WHERE families_fts MATCH ?

      UNION ALL

      SELECT id, name, common_name_en, common_name_de, common_name_fr, common_name_es, 'orders' AS entity_type, NULL as external_source, NULL as external_id
      FROM orders_fts
      WHERE orders_fts MATCH ?

      UNION ALL

      SELECT id, name, NULL AS common_name_en, NULL AS common_name_de, NULL AS common_name_fr, NULL AS common_name_es, 'classes' AS entity_type, NULL as external_source, NULL as external_id
      FROM classes_fts
      WHERE classes_fts MATCH ?
    
  ''', [wildcardTerm, wildcardTerm, wildcardTerm, wildcardTerm, wildcardTerm]);

    return results.map((row) => _mapRowToSearchResult(row)).toList();
  }

  SearchResult _mapRowToSearchResult(Map<String, dynamic> row) {
    // Bestimme den Typ basierend auf dem String-Wert aus der DB
    final String entityTypeString = row['entity_type'] as String;
    late final SearchEntityType type;
    switch (entityTypeString) {
      case 'species':
        type = SearchEntityType.species;
        break;
      case 'genera':
        type = SearchEntityType.genus;
        break;
      case 'families':
        type = SearchEntityType.family;
        break;
      case 'orders':
        type = SearchEntityType.order;
        break;
      case 'classes':
        type = SearchEntityType.classType;
        break;
      default:
        throw Exception('Unbekannter Entity-Typ: $entityTypeString');
    }

    String resultIdStr = row['id'] as String;
    if (type == SearchEntityType.species) {
        final String? src = row['external_source'] as String?;
        final String? extId = row['external_id'] as String?;
        if (src != null && extId != null) {
            resultIdStr = "$src:$extId";
        }
    }

    return SearchResult(
      id: resultIdStr,
      name: row['name'] as String,
      commonNames: {
        Language.en: row['common_name_en'] as String?,
        Language.de: row['common_name_de'] as String?,
        Language.fr: row['common_name_fr'] as String?,
        Language.es: row['common_name_es'] as String?,
      },
      type: type,
    );
  }
}
