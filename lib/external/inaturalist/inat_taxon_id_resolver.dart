import 'dart:convert';
import 'package:discere/external/inaturalist/inat_ancestry_requirement.dart';
import 'package:discere/external/inaturalist/inat_api_client.dart';
import 'package:discere/external/inaturalist/request_memo.dart';
import 'package:http/http.dart' as http;

/// Thrown when an iNaturalist taxon search succeeds but yields no taxon the
/// name may be resolved to — none at all, none that fits, or one that must
/// not be searched for — a permanent outcome, unlike a network error or
/// timeout, which should still be retried later.
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
/// Search answers are remembered and concurrent searches for the same name
/// share one request — enrichment resolves the same taxon for several species
/// at once, against an API that rate-limits.
///
/// A hit is only taken when it is the one taxon that fits: never the
/// search's first result for want of a better one, and never one of two that
/// fit equally. With an [INatAncestryRequirement] it must also sit under the
/// phyla (and classes) the reference data allows; a name alone does not tell
/// homonyms apart, and photos or names of another organism are worse than
/// none.
class INatTaxonIdResolver {
  final INatApiClient _api;

  /// Keyed by rank and name; which hit a caller takes depends on what it
  /// asks for, so the raw hits are what is worth sharing.
  late final RequestMemo<String, List<_TaxonSearchHit>> _searchMemo =
      RequestMemo(
        isWorthKeeping: (_) => true,
        onMemoHit: (key) =>
            INatApiClient.logDebug('iNat taxon search memo hit "$key"'),
      );

  INatTaxonIdResolver({required INatApiClient api}) : _api = api;

  static const _taxonSearchFields = 'id,name,rank,matched_term,ancestor_ids';

  /// The species taxon id for [scientificName], or null when the search
  /// failed. [taxonId] short-circuits when the caller already knows it.
  /// Throws [TaxonNotFoundException] when the search is conclusive: no
  /// result, or none that fits.
  ///
  /// A hit carrying exactly the name wins; without one, a hit that matches
  /// it as a synonym (`matched_term`). Searching on `rank=species` only
  /// returns species, so a synonym hit is mostly the same species under a
  /// new genus name, and where iNaturalist has merged two species, its view
  /// is taken. Either kind must meet [ancestry] when given — without it, a
  /// reference database that cannot say which phyla fit, only the name
  /// decides.
  Future<int?> resolve(
    String scientificName, {
    int? taxonId,
    INatAncestryRequirement? ancestry,
  }) async {
    if (taxonId != null) return taxonId;

    final List<_TaxonSearchHit> hits;
    try {
      hits = await _search(scientificName, rank: 'species');
    } on http.ClientException catch (e) {
      INatApiClient.logDebug('iNat resolve taxon failed: $e');
      return null;
    }

    final named = hits.where((hit) => hit.isNamed(scientificName));
    final synonyms = hits.where(
      (hit) => !hit.isNamed(scientificName) && hit.matches(scientificName),
    );
    final acceptedNamed = _fitting(named, ancestry);
    final resolvedId = acceptedNamed.isNotEmpty
        ? _single(acceptedNamed)
        : _single(_fitting(synonyms, ancestry));
    if (resolvedId == null) {
      INatApiClient.logDebug(
        'iNat resolve taxon none for "$scientificName" '
        '(${hits.length} results)',
      );
      throw TaxonNotFoundException(scientificName);
    }
    INatApiClient.logDebug(
      'iNat resolve taxon matched "$scientificName" -> $resolvedId',
    );
    return resolvedId;
  }

  /// The id of the taxon named exactly [scientificName] on exactly [rank],
  /// for the ranks above species.
  ///
  /// Stricter than [resolve] on purpose: a synonym hit is a different taxon
  /// often enough (Sebastidae matching Scorpaenidae through a synonym) that
  /// its names would be wrong, and a wrong name is worse than none. The hit
  /// must meet [ancestry] when given. Throws [TaxonNotFoundException] when no
  /// single result fits, and an [http.ClientException] or a timeout when the
  /// search itself failed.
  Future<int> resolveExact(
    String scientificName, {
    required String rank,
    INatAncestryRequirement? ancestry,
  }) async {
    final hits = await _search(scientificName, rank: rank);
    final resolvedId = _single(
      _fitting(
        hits.where((hit) => hit.rank == rank && hit.isNamed(scientificName)),
        ancestry,
      ),
    );
    if (resolvedId == null) {
      INatApiClient.logDebug(
        'iNat exact taxon none for "$scientificName" ($rank)',
      );
      throw TaxonNotFoundException(scientificName);
    }
    INatApiClient.logDebug(
      'iNat exact taxon matched "$scientificName" ($rank) -> $resolvedId',
    );
    return resolvedId;
  }

  static List<_TaxonSearchHit> _fitting(
    Iterable<_TaxonSearchHit> hits,
    INatAncestryRequirement? ancestry,
  ) => [
    for (final hit in hits)
      if (ancestry == null || ancestry.isMetBy(hit.ancestorIds)) hit,
  ];

  /// The id when exactly one taxon is left; two that fit equally are a
  /// homonym the search cannot settle.
  static int? _single(List<_TaxonSearchHit> hits) {
    final ids = {for (final hit in hits) hit.id};
    return ids.length == 1 ? ids.single : null;
  }

  Future<List<_TaxonSearchHit>> _search(
    String scientificName, {
    required String rank,
  }) => _searchMemo.fetch(
    '${rank.trim().toLowerCase()}:${scientificName.trim().toLowerCase()}',
    () => _searchUncached(scientificName, rank: rank),
  );

  Future<List<_TaxonSearchHit>> _searchUncached(
    String scientificName, {
    required String rank,
  }) async {
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
    final response = await _api
        .get(searchUri)
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw http.ClientException(
        'iNat taxon search for "$scientificName" ($rank) failed with status '
        '${response.statusCode}',
      );
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return [
      for (final result in data['results'] as List<dynamic>? ?? const [])
        ?_TaxonSearchHit.fromJson(result as Map<String, dynamic>),
    ];
  }
}

/// One result of a taxon search, with what [INatTaxonIdResolver] decides on.
final class _TaxonSearchHit {
  final int id;
  final String name;
  final String? rank;
  final String? matchedTerm;
  final List<int> ancestorIds;

  const _TaxonSearchHit({
    required this.id,
    required this.name,
    required this.rank,
    required this.matchedTerm,
    required this.ancestorIds,
  });

  static _TaxonSearchHit? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! int) return null;
    return _TaxonSearchHit(
      id: id,
      name: json['name'] as String? ?? '',
      rank: json['rank'] as String?,
      matchedTerm: json['matched_term'] as String?,
      ancestorIds: [
        for (final ancestorId in json['ancestor_ids'] as List<dynamic>? ?? [])
          if (ancestorId is int) ancestorId,
      ],
    );
  }

  bool isNamed(String scientificName) => _sameName(name, scientificName);

  bool matches(String scientificName) =>
      matchedTerm != null && _sameName(matchedTerm!, scientificName);

  static bool _sameName(String left, String right) =>
      left.trim().toLowerCase() == right.trim().toLowerCase();
}
