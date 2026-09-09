import 'package:discere/external/inaturalist/inat_api_client.dart';
import 'package:discere/external/inaturalist/request_memo.dart';
import 'package:discere/shared/util/background_json.dart';
import 'package:http/http.dart' as http;
/// Fetches what iNaturalist knows about a taxon, by id.
///
/// Everything a caller wants from a taxon — its photos, its Wikipedia page,
/// its conservation status — comes out of the same detail document, so it is
/// fetched once and remembered rather than once per question.
///
/// [prefetch] exists because enrichment knows the whole batch of taxa up
/// front: asking for them together turns dozens of requests into a handful,
/// which matters against an API that rate-limits.
class INatTaxonDetails {
  /// How many taxon ids fit in one batched request.
  static const _batchSize = 30;

  final INatApiClient _api;

  late final RequestMemo<
    int,
    ({Map<String, dynamic>? taxonDetail, bool retryableFailure})
  >
  _memo = RequestMemo(isWorthKeeping: (result) => result.taxonDetail != null);

  INatTaxonDetails({required INatApiClient api}) : _api = api;

  static const Map<String, Object> _detailFields = {
    'id': true,
    'name': true,
    'rank': true,
    'preferred_common_name': true,
    'iconic_taxon_name': true,
    'wikipedia_url': true,
    'wikipedia_summary': true,
    'conservation_status': {'status': true, 'authority': true},
    'conservation_statuses': {'status': true, 'authority': true},
    'default_photo': {
      'id': true,
      'url': true,
      'medium_url': true,
      'license_code': true,
      'attribution': true,
    },
    'taxon_photos': {
      'photo': {
        'id': true,
        'url': true,
        'medium_url': true,
        'license_code': true,
        'attribution': true,
      },
    },
  };

  Future<void> prefetch(Iterable<int> taxonIds) async {
    final uniqueTaxonIds = taxonIds.toSet().toList()..sort();
    final missingTaxonIds = uniqueTaxonIds
        .where((taxonId) => !_memo.containsKey(taxonId))
        .toList(growable: false);
    if (missingTaxonIds.isEmpty) return;

    for (final chunk in chunked(missingTaxonIds, _batchSize)) {
      try {
        final detailsById = await _fetchBatch(chunk);
        for (final entry in detailsById.entries) {
          _memo.remember(entry.key, (
            taxonDetail: entry.value,
            retryableFailure: false,
          ));
        }
      } catch (e) {
        INatApiClient.logDebug('iNat taxon detail prefetch failed for $chunk: $e');
      }
    }
  }

  /// Fetches a single taxon record by ID to retrieve the curated gallery.
  /// The detail document for [taxonId]. `retryableFailure` distinguishes
  /// a transient failure, which is worth another attempt later, from a
  /// taxon that simply has nothing.
  Future<({Map<String, dynamic>? taxonDetail, bool retryableFailure})>
  fetch(int taxonId) =>
      _memo.fetch(taxonId, () => _fetchUncached(taxonId));

  Future<({Map<String, dynamic>? taxonDetail, bool retryableFailure})>
  _fetchUncached(int taxonId) async {
    final stopwatch = Stopwatch()..start();
    try {
      final uri = _api.uri('/taxa/$taxonId');
      final response = await _api.get(
        uri,
        fields: _detailFields,
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        INatApiClient.logDebug(
          'iNat taxon detail failed (taxon=$taxonId, '
          'status=${response.statusCode}, ${stopwatch.elapsedMilliseconds}ms)',
        );
        return (
          taxonDetail: null,
          retryableFailure: INatApiClient.isRetryableStatus(response.statusCode),
        );
      }

      final data = Map<String, dynamic>.from(
        ((await BackgroundJson.decodeBytes(response.bodyBytes)) as Map)
            .cast<Object?, Object?>(),
      );
      final results = data['results'] as List<dynamic>?;
      if (results == null || results.isEmpty) {
        INatApiClient.logDebug(
          'iNat taxon detail empty (taxon=$taxonId, '
          '${stopwatch.elapsedMilliseconds}ms)',
        );
        return (taxonDetail: null, retryableFailure: false);
      }

      INatApiClient.logDebug(
        'iNat taxon detail ok (taxon=$taxonId, '
        '${stopwatch.elapsedMilliseconds}ms)',
      );
      return (
        taxonDetail: results.first as Map<String, dynamic>,
        retryableFailure: false,
      );
    } catch (e) {
      INatApiClient.logDebug(
        'iNat taxon detail error (taxon=$taxonId, '
        '${stopwatch.elapsedMilliseconds}ms): $e',
      );
      return (taxonDetail: null, retryableFailure: true);
    }
  }

  Future<Map<int, Map<String, dynamic>>> _fetchBatch(
    List<int> taxonIds,
  ) async {
    if (taxonIds.isEmpty) return const <int, Map<String, dynamic>>{};

    final sortedTaxonIds = [...taxonIds]..sort();
    final path = '/taxa/${sortedTaxonIds.join(',')}';
    final uri = _api.uri(path);
    final response = await _api.get(
      uri,
      fields: _detailFields,
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw http.ClientException(
        'Batch taxon detail request failed with status ${response.statusCode}',
        uri,
      );
    }

    final data = Map<String, dynamic>.from(
      ((await BackgroundJson.decodeBytes(response.bodyBytes)) as Map)
          .cast<Object?, Object?>(),
    );
    final results = data['results'] as List<dynamic>?;
    if (results == null || results.isEmpty) {
      return const <int, Map<String, dynamic>>{};
    }

    final detailsById = <int, Map<String, dynamic>>{};
    for (final row in results.whereType<Map<String, dynamic>>()) {
      final id = row['id'] as int?;
      if (id == null) continue;
      detailsById[id] = row;
    }
    INatApiClient.logDebug(
      'iNat taxon detail batch ok '
      '(requested=${sortedTaxonIds.length}, received=${detailsById.length})',
    );
    return detailsById;
  }
}
