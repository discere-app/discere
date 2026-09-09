/// Turns the rows a search produced into one ordered list of results.
///
/// A term is looked up in five places at once — the reference DB, downloaded
/// decks, their fallbacks, iNaturalist, and a reference fallback — and the
/// same species can come back from several of them, spelled differently and
/// with different common names. What the user sees depends entirely on how
/// those are merged and ordered.
///
/// Kept apart from [SearchWorker] because none of it needs an isolate: it is
/// a judgement about rows, and it should be checkable as one. Inside the
/// worker's entrypoint it was reachable only by sending a message.
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

  final localizedCompare = _localizedCommonNameWeight(
    b,
  ).compareTo(_localizedCommonNameWeight(a));
  if (localizedCompare != 0) return localizedCompare;

  final sourceCompare = a.sourcePriority.compareTo(b.sourcePriority);
  if (sourceCompare != 0) return sourceCompare;

  return a.name.toLowerCase().compareTo(b.name.toLowerCase());
}

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
}) {
  if (normalizedSearchTerm.isEmpty) return isFallback ? 2 : 1;

  final searchableValues = <String>[
    row['scientific_name'] as String? ?? '',
    row['common_name_en'] as String? ?? '',
    row['common_name_de'] as String? ?? '',
    row['common_name_fr'] as String? ?? '',
    row['common_name_es'] as String? ?? '',
  ];

  final normalizedCandidates = searchableValues
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

  const SearchCandidate({
    required this.stableKey,
    required this.id,
    required this.name,
    required this.commonNames,
    required this.type,
    required this.matchPriority,
    required this.sourcePriority,
  });

  SearchCandidate merge(SearchCandidate other) {
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
    );
  }
}

