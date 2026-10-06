import 'dart:convert';
import 'package:discere/external/inaturalist/inat_api_client.dart';
import 'package:discere/external/inaturalist/request_memo.dart';
import 'package:http/http.dart' as http;
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

  /// Separate from [_taxonIdMemo] so that a lax species-style answer — a
  /// synonym hit, the first result — is never handed out as an exact one.
  late final RequestMemo<String, int> _exactTaxonIdMemo = RequestMemo(
    isWorthKeeping: (_) => true,
    onMemoHit: (key) =>
        INatApiClient.logDebug('iNat exact taxon memo hit "$key"'),
  );

  INatTaxonIdResolver({required INatApiClient api}) : _api = api;

  static const _taxonSearchFields =
      'id,name,rank,preferred_common_name,matched_term';

  /// Checks if the API result is a relevant match for the query.
  bool _isRelevantMatch(String query, String result) {
    return result.toLowerCase().trim() == query.toLowerCase().trim();
  }

  /// The species taxon id for [scientificName], or null when iNaturalist has
  /// nothing usable. [taxonId] short-circuits when the caller already knows
  /// it. Throws [TaxonNotFoundException] when the search is conclusive.
  Future<int?> resolve(String scientificName, {int? taxonId}) {
    if (taxonId != null) return Future.value(taxonId);
    return _taxonIdMemo.fetch(
      scientificName.trim().toLowerCase(),
      () => _resolveTaxonIdUncached(scientificName),
    );
  }

  /// The id of the taxon named exactly [scientificName] on exactly [rank],
  /// for the ranks above species.
  ///
  /// Stricter than [resolve] on purpose: a synonym hit or the search's first
  /// result is a different taxon often enough (Sebastidae matching
  /// Scorpaenidae through a synonym) that its names would be wrong, and a
  /// wrong name is worse than none. Throws [TaxonNotFoundException] when no
  /// result matches, and an [http.ClientException] or a timeout when the
  /// search itself failed.
  Future<int> resolveExact(String scientificName, {required String rank}) {
    return _exactTaxonIdMemo.fetch(
      '${rank.trim().toLowerCase()}:${scientificName.trim().toLowerCase()}',
      () => _resolveExactUncached(scientificName, rank: rank),
    );
  }

  Future<int?> _resolveTaxonIdUncached(String scientificName) async {
    final stopwatch = Stopwatch()..start();
    final searchResponse = await _searchTaxa(scientificName, rank: 'species');

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

  Future<int> _resolveExactUncached(
    String scientificName, {
    required String rank,
  }) async {
    final response = await _searchTaxa(scientificName, rank: rank);
    if (response.statusCode != 200) {
      throw http.ClientException(
        'iNat taxon search for "$scientificName" ($rank) failed with status '
        '${response.statusCode}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    for (final r in data['results'] as List<dynamic>? ?? const []) {
      final resolvedId = r['id'] as int?;
      if (resolvedId != null &&
          r['rank'] == rank &&
          _isRelevantMatch(scientificName, r['name'] as String? ?? '')) {
        INatApiClient.logDebug(
          'iNat exact taxon matched "$scientificName" ($rank) -> $resolvedId',
        );
        return resolvedId;
      }
    }
    INatApiClient.logDebug('iNat exact taxon none for "$scientificName" ($rank)');
    throw TaxonNotFoundException(scientificName);
  }

  Future<http.Response> _searchTaxa(
    String scientificName, {
    required String rank,
  }) {
    final searchUri = _api.uri(
      '/taxa',
      queryParameters: {
        'q': scientificName.trim(),
        'per_page': '10',
        'fields': _taxonSearchFields,
      },
      queryParametersAll: {
        'rank': [rank],
      },
    );
    return _api.get(searchUri).timeout(const Duration(seconds: 10));
  }
}
