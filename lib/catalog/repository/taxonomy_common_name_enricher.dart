import 'package:discere/catalog/model/search_result.dart';
import 'package:discere/catalog/model/taxon_rank.dart';
import 'package:discere/catalog/model/taxonomy_detail.dart';
import 'package:discere/catalog/repository/common_name_merging.dart';
import 'package:discere/catalog/repository/common_name_repository.dart';
import 'package:discere/shared/model/language.dart';
import 'package:sqflite/sqflite.dart';

/// Adds the names fetched from iNaturalist to what the taxonomy page shows.
///
/// The reference DB names a taxon, its ancestors and its children; the user
/// DB's `runtime_common_names` holds what enrichment fetched for the same
/// taxa — a higher rank keyed by rank and scientific name, a species by its
/// id. Each name list on the page gets both, merged the way the species page
/// merges its classification, so one family reads the same on either page.
///
/// One `runtime_common_names` read per page: a family can have hundreds of
/// genera, and every one of them is looked up in the same query.
class TaxonomyCommonNameEnricher {
  final CommonNameRepository _commonNameRepository;
  final Future<Database?> Function() _userDatabase;

  const TaxonomyCommonNameEnricher(
    this._commonNameRepository, {
    required Future<Database?> Function() userDatabase,
  }) : _userDatabase = userDatabase;

  /// [detail] with runtime names merged into its own names and into those
  /// of each classification entry.
  ///
  /// [detail]'s own names are expected to already have the reference name
  /// filled in where the search result had none — the runtime names are
  /// merged on top of that, not underneath it.
  Future<TaxonomyDetail> enrichDetail(TaxonomyDetail detail) async {
    final ownKey = _keyOf(detail.result);
    final names = await _load({
      ownKey,
      ...detail.classification.map(_keyOfEntry).nonNulls,
    });
    if (names.isEmpty) return detail;

    return TaxonomyDetail(
      result: detail.result,
      commonNames: _merged(detail.commonNames, names[ownKey]),
      classification: [
        for (final entry in detail.classification)
          TaxonomyClassificationEntry(
            label: entry.label,
            id: entry.id,
            scientificName: entry.scientificName,
            commonNames: _merged(entry.commonNames, names[_keyOfEntry(entry)]),
          ),
      ],
      metrics: detail.metrics,
      attributes: detail.attributes,
      isReferenceBacked: detail.isReferenceBacked,
    );
  }

  /// [children] with each one's runtime names merged into its own.
  Future<List<SearchResult>> enrichChildren(List<SearchResult> children) async {
    final names = await _load(children.map(_keyOf).toSet());
    if (names.isEmpty) return children;

    return [
      for (final child in children)
        SearchResult(
          id: child.id,
          name: child.name,
          commonNames: _merged(child.commonNames, names[_keyOf(child)]),
          type: child.type,
        ),
    ];
  }

  /// Without a user DB there is nothing fetched to add, so nothing is read.
  Future<Map<String, Map<Language, List<String>>>> _load(
    Set<String> entityKeys,
  ) async {
    final userDb = await _userDatabase();
    if (userDb == null) return const {};
    return _commonNameRepository.loadRuntimeCommonNames(userDb, entityKeys);
  }

  Map<Language, List<String>> _merged(
    Map<Language, List<String>> reference,
    Map<Language, List<String>>? runtime,
  ) => runtime == null
      ? reference
      : mergeLocalizedCommonNames(reference, runtime);

  /// A species is keyed by its reference id, like on the species page: its
  /// scientific name is not what enrichment stores it under.
  String _keyOf(SearchResult result) => result.type == SearchEntityType.species
      ? 'species:${result.id}'
      : TaxonRank.fromSearchEntityType(result.type).entityKey(result.name);

  /// Null for a superclass: enrichment fetches no names at that rank.
  String? _keyOfEntry(TaxonomyClassificationEntry entry) {
    final rank = switch (entry.label) {
      TaxonomyRankLabel.family => TaxonRank.family,
      TaxonomyRankLabel.order => TaxonRank.order,
      TaxonomyRankLabel.classType => TaxonRank.classRank,
      TaxonomyRankLabel.superClass => null,
    };
    return rank?.entityKey(entry.scientificName);
  }
}
