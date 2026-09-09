import 'dart:convert';
import 'package:discere/external/inaturalist/inat_api_client.dart';
import 'package:discere/external/inaturalist/request_memo.dart';
/// Thrown when an iNaturalist taxon search succeeds but confirms the
/// scientific name matches no taxon at all — a permanent outcome, unlike a
/// network error or timeout, which should still be retried later.
final class TaxonNotFoundException implements Exception {
  final String scientificName;

  const TaxonNotFoundException(this.scientificName);

  @override
  String toString() => 'TaxonNotFoundException: "$scientificName"';
}

/// Finds the iNaturalist taxon id for a scientific name.
///
/// Everything else the app asks iNaturalist for is keyed by that id, so this
/// sits under the rest rather than beside it.
///
/// Answers are remembered and concurrent lookups of the same name share one
/// request — enrichment resolves the same taxon for several species at once,
/// against an API that rate-limits.
class INatTaxonIdResolver {
  final INatApiClient _api;

  late final RequestMemo<String, int?> _taxonIdMemo = RequestMemo(
    isWorthKeeping: (taxonId) => taxonId != null,
    onMemoHit: (key) =>
        INatApiClient.logDebug('iNat resolve taxon memo hit "$key"'),
  );

  INatTaxonIdResolver({required INatApiClient api}) : _api = api;

  static const _taxonSearchFields =
      'id,name,rank,preferred_common_name,matched_term';

  /// Checks if the API result is a relevant match for the query.
  bool _isRelevantMatch(String query, String result) {
    return result.toLowerCase().trim() == query.toLowerCase().trim();
  }

  /// The taxon id for [scientificName], or null when iNaturalist has
  /// nothing usable. [taxonId] short-circuits when the caller already knows
  /// it. Throws [TaxonNotFoundException] when the search is conclusive.
  Future<int?> resolve(
    String scientificName, {
    int? taxonId,
    String? rank,
  }) {
    if (taxonId != null) return Future.value(taxonId);
    return _taxonIdMemo.fetch(
      _taxonResolveMemoKey(scientificName, rank: rank),
      () => _resolveTaxonIdUncached(scientificName, rank: rank),
    );
  }

  Future<int?> _resolveTaxonIdUncached(
    String scientificName, {
    String? rank,
  }) async {
    final stopwatch = Stopwatch()..start();
    final normalizedRank = (rank != null && rank.trim().isNotEmpty)
        ? rank.trim()
        : 'species';

    final searchUri = _api.uri(
      '/taxa',
      queryParameters: {
        'q': scientificName.trim(),
        'per_page': '10',
        'fields': _taxonSearchFields,
      },
      queryParametersAll: {
        'rank': [normalizedRank],
      },
    );

    final searchResponse = await _api
        .get(searchUri)
        .timeout(const Duration(seconds: 10));

    if (searchResponse.statusCode != 200) {
      INatApiClient.logDebug(
        'iNat resolve taxon failed for "$scientificName" '
        '(status=${searchResponse.statusCode}, '
        '${stopwatch.elapsedMilliseconds}ms)',
      );
      return null;
    }

    final searchData = jsonDecode(searchResponse.body) as Map<String, dynamic>;
    final results = searchData['results'] as List<dynamic>?;
    if (results == null || results.isEmpty) {
      INatApiClient.logDebug(
        'iNat resolve taxon empty for "$scientificName" '
        '(${stopwatch.elapsedMilliseconds}ms)',
      );
      throw TaxonNotFoundException(scientificName);
    }

    for (final r in results) {
      final name = r['name'] as String? ?? '';
      final matchedTerm = r['matched_term'] as String?;

      if (_isRelevantMatch(scientificName, name) ||
          (matchedTerm != null &&
              _isRelevantMatch(scientificName, matchedTerm))) {
        final resolvedId = r['id'] as int?;
        INatApiClient.logDebug(
          'iNat resolve taxon matched "$scientificName" -> $resolvedId '
          '(${stopwatch.elapsedMilliseconds}ms)',
        );
        return resolvedId;
      }
    }

    final fallbackId = results.first['id'] as int?;
    INatApiClient.logDebug(
      'iNat resolve taxon fallback "$scientificName" -> $fallbackId '
      '(${stopwatch.elapsedMilliseconds}ms)',
    );
    return fallbackId;
  }

  String _taxonResolveMemoKey(String scientificName, {String? rank}) {
    final normalizedRank = (rank?.trim().toLowerCase().isNotEmpty ?? false)
        ? rank!.trim().toLowerCase()
        : 'species';
    final normalizedName = scientificName.trim().toLowerCase();
    return '$normalizedRank:$normalizedName';
  }
}
