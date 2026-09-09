import 'package:discere/external/inaturalist/inat_api_client.dart';
import 'package:discere/external/inaturalist/inat_common_name_ranking.dart';
import 'package:discere/external/inaturalist/inat_taxon_id_resolver.dart';
import 'package:discere/external/inaturalist/models/inat_common_name.dart';
import 'package:discere/shared/util/background_json.dart';
import 'package:discere/shared/util/logger.dart';

/// Fetches the common names iNaturalist has for a taxon, per language.
///
/// Reads them off the legacy `taxon_names.json` endpoint, which is the only
/// one that returns all of them with their place associations — the v2 API
/// gives one preferred name per language and no way to rank alternatives.
class INatCommonNameApi {
  static final _log = Logger.forType(INatCommonNameApi);

  final INatApiClient _api;
  final INatTaxonIdResolver _taxonIds;

  const INatCommonNameApi({
    required INatApiClient api,
    required INatTaxonIdResolver taxonIds,
  }) : _api = api,
       _taxonIds = taxonIds;

  /// Fetches ranked common names for a taxon.
  ///
  /// Supports species and higher taxonomy ranks. The returned map is keyed by
  /// app language code (`de`, `en`, `fr`, `es`) and values are ordered from
  /// best to worst candidate according to iNaturalist ranking metadata.
  Future<({int taxonId, Map<String, List<INatCommonName>> commonNames})?>
  fetchCommonNames(String scientificName, {int? taxonId, String? rank}) async {
    try {
      final resolvedTaxonId = await _taxonIds.resolve(
        scientificName,
        taxonId: taxonId,
        rank: rank,
      );
      if (resolvedTaxonId == null) return null;

      final uri = Uri.https(INatApiClient.legacyWebHost, '/taxon_names.json', {
        'taxon_id': resolvedTaxonId.toString(),
        'per_page': '200',
      });
      final response = await _api
          .get(uri)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return null;

      final decoded = await BackgroundJson.decodeBytes(response.bodyBytes);
      final rows = taxonNameRowsOf(decoded);
      final namesByLanguage = <String, List<INatCommonName>>{};

      for (final row in rows) {
        final commonName = parseCommonName(row);
        if (commonName == null) continue;
        namesByLanguage
            .putIfAbsent(commonName.languageCode, () => [])
            .add(commonName);
      }

      final result = <String, List<INatCommonName>>{};
      for (final entry in namesByLanguage.entries) {
        final ranked = rankCommonNames(entry.value);
        if (ranked.isNotEmpty) result[entry.key] = ranked;
      }

      return (taxonId: resolvedTaxonId, commonNames: result);
    } on TaxonNotFoundException {
      rethrow;
    } catch (e) {
      _log.warn('fetchCommonNames failed for "$scientificName": $e');
      return null;
    }
  }
}
