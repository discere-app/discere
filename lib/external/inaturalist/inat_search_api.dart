
import 'package:discere/external/inaturalist/inat_api_client.dart';
import 'package:discere/shared/util/background_json.dart';
import 'package:discere/shared/util/logger.dart';

/// Free-text taxon search against iNaturalist.
///
/// Used where the app has a name and needs candidates to show or to match
/// against — the catalog's reference resolver and enrichment's name
/// resolution. Distinct from [INatTaxonIdResolver], which answers the
/// narrower question of which single taxon a known scientific name is.
class INatSearchApi {
  static final _log = Logger.forType(INatSearchApi);

  final INatApiClient _api;

  const INatSearchApi({required INatApiClient api}) : _api = api;

  static const Map<String, Object> _taxonSearchFieldsExpanded = {
    'id': true,
    'name': true,
    'rank': true,
    'preferred_common_name': true,
    'matched_term': true,
    'iconic_taxon_name': true,
    'default_photo': {
      'id': true,
      'url': true,
      'medium_url': true,
      'license_code': true,
    },
  };

  /// Searches iNaturalist taxa by a free-text query (scientific or common name).
  ///
  /// Returns up to [perPage] active candidates across the taxonomic ranks that
  /// Discere can surface in search. Each entry contains the scientific name,
  /// the iNat taxon ID, the taxon rank, and the preferred common name if
  /// available. Returns an empty list on network errors or timeouts so callers
  /// can treat this as a best-effort supplement.
  Future<List<Map<String, dynamic>>> searchTaxa(
    String query, {
    int perPage = 20,
  }) async {
    try {
      final uri = _api.uri(
        '/taxa',
        queryParameters: {
          'q': query.trim(),
          'per_page': perPage.toString(),
          'is_active': 'true',
        },
        queryParametersAll: {
          'rank': const [
            'class',
            'order',
            'family',
            'genus',
            'species',
            'subspecies',
          ],
        },
      );

      final response = await _api.get(
        uri,
        fields: _taxonSearchFieldsExpanded,
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) return const [];

      final data = Map<String, dynamic>.from(
        ((await BackgroundJson.decodeBytes(response.bodyBytes)) as Map)
            .cast<Object?, Object?>(),
      );
      final results = data['results'] as List<dynamic>?;
      if (results == null) return const [];

      return results.whereType<Map<String, dynamic>>().map((r) {
        final defaultPhoto = r['default_photo'] as Map<String, dynamic>?;
        return <String, dynamic>{
          'id': r['id'] as int?,
          'scientific_name': r['name'] as String? ?? '',
          'rank': r['rank'] as String? ?? '',
          'preferred_common_name': r['preferred_common_name'] as String?,
          'matched_term': r['matched_term'] as String?,
          'iconic_taxon_name': r['iconic_taxon_name'] as String?,
          'default_photo_url': defaultPhoto?['url'] as String?,
          'default_photo_medium_url': defaultPhoto?['medium_url'] as String?,
          'default_photo_license_code':
              defaultPhoto?['license_code'] as String?,
        };
      }).toList();
    } catch (e) {
      _log.warn('searchTaxa failed for "$query": $e');
      return const [];
    }
  }
}
