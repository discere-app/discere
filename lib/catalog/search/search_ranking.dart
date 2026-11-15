/// Turns the rows a search produced into one ordered list of results.
///
/// A term is looked up in six places at once — the reference DB, the
/// synonyms of its species, downloaded decks, their fallbacks, iNaturalist,
/// and a reference fallback — and the same species can come back from
/// several of them, spelled differently and with different common names.
/// What the user sees depends entirely on how those are merged and ordered.
///
/// Kept apart from [SearchWorker] because none of it needs an isolate: it is
/// a judgement about rows, and it should be checkable as one, without
/// sending a message to the worker.
library;

import 'package:discere/catalog/model/search_result.dart';
import 'package:discere/catalog/util/search_text.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/util/common_name_utils.dart';

SearchCandidate candidateFromReferenceRow(
  Map<String, dynamic> row, {
  required String normalizedSearchTerm,
  int sourcePriority = 1,
}) {
  return SearchCandidate(
    stableKey: _stableKeyForEntity(
      entityType: row['entity_type'] as String,
      entityId: row['id'] as String,
      scientificName: row['scientific_name'] as String,
    ),
    id: row['id'] as String,
    name: row['scientific_name'] as String,
    commonNames: _commonNamesFromRow(row),
    type: _entityTypeFromString(row['entity_type'] as String),
    matchPriority: _matchPriorityFromRow(
      row,
      normalizedSearchTerm: normalizedSearchTerm,
      isFallback: false,
    ),
    sourcePriority: sourcePriority,
  );
}

/// A species found through one of its synonyms, carried by the row as
/// `matched_synonym`. Ranked by how well that synonym matches the term: the
/// species' current name, which the row carries as `scientific_name`, is not
/// what the user typed.
SearchCandidate candidateFromSynonymRow(
  Map<String, dynamic> row, {
  required String normalizedSearchTerm,
}) {
  final synonym = row['matched_synonym'] as String;
  return SearchCandidate(
    stableKey: _stableKeyForEntity(
      entityType: row['entity_type'] as String,
      entityId: row['id'] as String,
      scientificName: row['scientific_name'] as String,
    ),
    id: row['id'] as String,
    name: row['scientific_name'] as String,
    commonNames: _commonNamesFromRow(row),
    type: _entityTypeFromString(row['entity_type'] as String),
    matchPriority: nameMatchPriority(
      [synonym],
      normalizedSearchTerm: normalizedSearchTerm,
    ),
    // Read from the reference DB like the reference rows; what sets a
    // synonym hit apart is decided by [compareCandidates] and
    // [SearchCandidate.merge], not by its source.
    sourcePriority: 1,
    matchedSynonym: synonym,
  );
}

SearchCandidate candidateFromDownloadedRow(
  Map<String, dynamic> row, {
  required String normalizedSearchTerm,
  bool isFallback = false,
}) {
  final entityType = row['entity_type'] as String;
  final entityId = row['entity_id'] as String? ?? row['id'] as String;
  final scientificName = row['scientific_name'] as String;

  return SearchCandidate(
    stableKey: _stableKeyForEntity(
      entityType: entityType,
      entityId: entityId,
      scientificName: scientificName,
    ),
    id: entityType == 'species' ? entityId : (row['id'] as String? ?? entityId),
    name: scientificName,
    commonNames: _commonNamesFromRow(row),
    type: _entityTypeFromString(entityType),
    matchPriority: _matchPriorityFromRow(
      row,
      normalizedSearchTerm: normalizedSearchTerm,
      isFallback: isFallback,
    ),
    sourcePriority: 0,
  );
}

List<SearchCandidate> mergeCandidates(List<SearchCandidate> candidates) {
  final mergedByKey = <String, SearchCandidate>{};
  for (final candidate in candidates) {
    final existing = mergedByKey[candidate.stableKey];
    if (existing == null) {
      mergedByKey[candidate.stableKey] = candidate;
      continue;
    }
    mergedByKey[candidate.stableKey] = existing.merge(candidate);
  }
  return mergedByKey.values.toList();
}

int compareCandidates(SearchCandidate a, SearchCandidate b) {
  final matchCompare = a.matchPriority.compareTo(b.matchPriority);
  if (matchCompare != 0) return matchCompare;

  // A species found under its current name answers the term more directly
  // than one found under a synonym that matches as well.
  final synonymCompare = _synonymWeight(a).compareTo(_synonymWeight(b));
  if (synonymCompare != 0) return synonymCompare;

  final localizedCompare = _localizedCommonNameWeight(
    b,
  ).compareTo(_localizedCommonNameWeight(a));
  if (localizedCompare != 0) return localizedCompare;

  final sourceCompare = a.sourcePriority.compareTo(b.sourcePriority);
  if (sourceCompare != 0) return sourceCompare;

  return a.name.toLowerCase().compareTo(b.name.toLowerCase());
}

int _synonymWeight(SearchCandidate candidate) =>
    candidate.matchedSynonym == null ? 0 : 1;

int _localizedCommonNameWeight(SearchCandidate candidate) {
  if ((candidate.commonNames[Language.en] ?? const []).isNotEmpty) return 2;
  if (candidate.commonNames.values.any((value) => value.isNotEmpty)) {
    return 1;
  }
  return 0;
}

Map<Language, List<String>> _commonNamesFromRow(Map<String, dynamic> row) {
  return {
    Language.en: splitCommonNames(row['common_name_en'] as String?),
    Language.de: splitCommonNames(row['common_name_de'] as String?),
    Language.fr: splitCommonNames(row['common_name_fr'] as String?),
    Language.es: splitCommonNames(row['common_name_es'] as String?),
  };
}

int _matchPriorityFromRow(
  Map<String, dynamic> row, {
  required String normalizedSearchTerm,
  required bool isFallback,
}) => nameMatchPriority(
  [
    row['scientific_name'] as String? ?? '',
    row['common_name_en'] as String? ?? '',
    row['common_name_de'] as String? ?? '',
    row['common_name_fr'] as String? ?? '',
    row['common_name_es'] as String? ?? '',
  ],
  normalizedSearchTerm: normalizedSearchTerm,
  isFallback: isFallback,
);

/// How well the best of [names] matches the term: 0 when one equals it, 1
/// when one starts with it, 2 otherwise — 3 for a fallback row, whose match
/// is weaker still. Each name may pack alternatives separated by `;`.
int nameMatchPriority(
  Iterable<String> names, {
  required String normalizedSearchTerm,
  bool isFallback = false,
}) {
  if (normalizedSearchTerm.isEmpty) return isFallback ? 2 : 1;

  final normalizedCandidates = names
      .expand((value) => value.split(';'))
      .map(normalizeSearchText)
      .where((value) => value.isNotEmpty)
      .toList();

  if (normalizedCandidates.contains(normalizedSearchTerm)) {
    return 0;
  }
  if (normalizedCandidates.any(
    (value) => value.startsWith(normalizedSearchTerm),
  )) {
    return 1;
  }
  return isFallback ? 3 : 2;
}

String _stableKeyForEntity({
  required String entityType,
  required String entityId,
  required String scientificName,
}) {
  if (entityType == 'species') {
    return 'species:$entityId';
  }
  return '$entityType:${scientificName.trim().toLowerCase()}';
}

SearchEntityType _entityTypeFromString(String entityType) {
  switch (entityType) {
    case 'species':
      return SearchEntityType.species;
    case 'genera':
      return SearchEntityType.genus;
    case 'families':
      return SearchEntityType.family;
    case 'orders':
      return SearchEntityType.order;
    case 'classes':
      return SearchEntityType.classType;
    default:
      throw StateError('Unknown entity type: $entityType');
  }
}

class SearchCandidate {
  final String stableKey;
  final String id;
  final String name;
  final Map<Language, List<String>> commonNames;
  final SearchEntityType type;
  final int matchPriority;
  final int sourcePriority;

  /// The synonym this species was found through; `null` for a direct hit.
  final String? matchedSynonym;

  const SearchCandidate({
    required this.stableKey,
    required this.id,
    required this.name,
    required this.commonNames,
    required this.type,
    required this.matchPriority,
    required this.sourcePriority,
    this.matchedSynonym,
  });

  SearchCandidate merge(SearchCandidate other) {
    // A species found directly is shown as found directly, whichever row
    // came first: the synonym hit neither labels it nor lifts its rank.
    if (matchedSynonym != null && other.matchedSynonym == null) return other;
    if (matchedSynonym == null && other.matchedSynonym != null) return this;

    final preferred = sourcePriority <= other.sourcePriority ? this : other;
    final secondary = identical(preferred, this) ? other : this;

    return SearchCandidate(
      stableKey: stableKey,
      id: preferred.id,
      name: preferred.name.length >= secondary.name.length
          ? preferred.name
          : secondary.name,
      commonNames: {
        for (final language in Language.values)
          language: deduplicateCommonNames([
            ...preferred.commonNames[language] ?? const [],
            ...secondary.commonNames[language] ?? const [],
          ]),
      },
      type: preferred.type,
      matchPriority: preferred.matchPriority < secondary.matchPriority
          ? preferred.matchPriority
          : secondary.matchPriority,
      sourcePriority: preferred.sourcePriority,
      matchedSynonym: preferred.matchedSynonym,
    );
  }
}

