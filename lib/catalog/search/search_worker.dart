import 'dart:async';
import 'dart:isolate';

import 'package:discere/catalog/model/search_result.dart';
import 'package:discere/catalog/repository/runtime_common_name_search_repository.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/util/common_name_utils.dart';

class SearchWorkerRequest {
  final int generation;
  final String normalizedSearchTerm;
  final List<Map<String, dynamic>> referenceRows;
  final List<Map<String, dynamic>> downloadedRows;
  final List<Map<String, dynamic>> fallbackRows;
  final List<Map<String, dynamic>> inatRows;
  final List<Map<String, dynamic>> referenceFallbackRows;

  const SearchWorkerRequest({
    required this.generation,
    required this.normalizedSearchTerm,
    this.referenceRows = const [],
    this.downloadedRows = const [],
    this.fallbackRows = const [],
    this.inatRows = const [],
    this.referenceFallbackRows = const [],
  });

  Map<String, dynamic> toMessage() {
    List<Map<String, dynamic>> cloneRows(List<Map<String, dynamic>> rows) {
      return rows.map((row) => Map<String, dynamic>.from(row)).toList();
    }

    return {
      'generation': generation,
      'normalizedSearchTerm': normalizedSearchTerm,
      'referenceRows': cloneRows(referenceRows),
      'downloadedRows': cloneRows(downloadedRows),
      'fallbackRows': cloneRows(fallbackRows),
      'inatRows': cloneRows(inatRows),
      'referenceFallbackRows': cloneRows(referenceFallbackRows),
    };
  }
}

class SearchWorkerResponse {
  final int generation;
  final bool isStale;
  final List<SearchResult> results;

  const SearchWorkerResponse({
    required this.generation,
    required this.isStale,
    required this.results,
  });
}

class SearchWorker {
  Future<SendPort>? _sendPortFuture;
  int _requestId = 0;

  Future<SearchWorkerResponse> process(SearchWorkerRequest request) async {
    final sendPort = await _ensureSendPort();
    final responsePort = ReceivePort();
    final requestId = ++_requestId;
    sendPort.send({
      'id': requestId,
      'replyPort': responsePort.sendPort,
      'payload': request.toMessage(),
    });

    final message = await responsePort.first as Map;
    responsePort.close();
    final results = ((message['results'] as List?) ?? const [])
        .whereType<Map>()
        .map(
          (row) => _searchResultFromMessage(
            Map<String, dynamic>.from(row.cast<Object?, Object?>()),
          ),
        )
        .toList();

    return SearchWorkerResponse(
      generation: message['generation'] as int? ?? request.generation,
      isStale: message['isStale'] as bool? ?? false,
      results: results,
    );
  }

  Future<void> dispose() async {
    final sendPortFuture = _sendPortFuture;
    if (sendPortFuture == null) return;
    final sendPort = await sendPortFuture;
    sendPort.send(const {'type': 'shutdown'});
    _sendPortFuture = null;
  }

  Future<SendPort> _ensureSendPort() {
    return _sendPortFuture ??= () async {
      final receivePort = ReceivePort();
      await Isolate.spawn(_searchWorkerMain, receivePort.sendPort);
      final sendPort = await receivePort.first as SendPort;
      receivePort.close();
      return sendPort;
    }();
  }
}

void _searchWorkerMain(SendPort initialReplyPort) {
  final commandPort = ReceivePort();
  initialReplyPort.send(commandPort.sendPort);
  var latestGeneration = 0;

  commandPort.listen((message) {
    if (message is Map && message['type'] == 'shutdown') {
      commandPort.close();
      return;
    }
    if (message is! Map) return;

    final replyPort = message['replyPort'] as SendPort;
    final payload = Map<String, dynamic>.from(
      (message['payload'] as Map).cast<Object?, Object?>(),
    );
    final generation = payload['generation'] as int? ?? 0;
    if (generation > latestGeneration) {
      latestGeneration = generation;
    }
    if (generation < latestGeneration) {
      replyPort.send({
        'generation': generation,
        'isStale': true,
        'results': const <Map<String, dynamic>>[],
      });
      return;
    }

    final results = _processSearchPayload(payload);
    final isStale = generation != latestGeneration;
    replyPort.send({
      'generation': generation,
      'isStale': isStale,
      'results': isStale ? const <Map<String, dynamic>>[] : results,
    });
  });
}

List<Map<String, dynamic>> _processSearchPayload(Map<String, dynamic> payload) {
  final normalizedSearchTerm = payload['normalizedSearchTerm'] as String? ?? '';
  final referenceRows = _messageRows(payload['referenceRows']);
  final downloadedRows = _messageRows(payload['downloadedRows']);
  final fallbackRows = _messageRows(payload['fallbackRows']);
  final inatRows = _messageRows(payload['inatRows']);
  final referenceFallbackRows = _messageRows(payload['referenceFallbackRows']);

  final mergedCandidates = _mergeCandidates([
    ...referenceRows.map(
      (row) => _candidateFromReferenceRow(
        row,
        normalizedSearchTerm: normalizedSearchTerm,
      ),
    ),
    ...downloadedRows.map(
      (row) => _candidateFromDownloadedRow(
        row,
        normalizedSearchTerm: normalizedSearchTerm,
      ),
    ),
    ...fallbackRows.map(
      (row) => _candidateFromDownloadedRow(
        row,
        normalizedSearchTerm: normalizedSearchTerm,
        isFallback: true,
      ),
    ),
    ...inatRows.map(
      (row) => _candidateFromReferenceRow(
        row,
        normalizedSearchTerm: normalizedSearchTerm,
        sourcePriority: 0,
      ),
    ),
    ...referenceFallbackRows.map(
      (row) => _candidateFromReferenceRow(
        row,
        normalizedSearchTerm: normalizedSearchTerm,
        sourcePriority: 2,
      ),
    ),
  ]);

  mergedCandidates.sort(_compareCandidates);
  return mergedCandidates.map(_searchResultToMessage).toList();
}

List<Map<String, dynamic>> _messageRows(Object? rawRows) {
  final rows = rawRows as List? ?? const [];
  return rows
      .whereType<Map>()
      .map((row) => Map<String, dynamic>.from(row.cast<Object?, Object?>()))
      .toList();
}

Map<String, dynamic> _searchResultToMessage(_SearchCandidate candidate) {
  return {
    'id': candidate.id,
    'name': candidate.name,
    'type': candidate.type.name,
    'commonNames': {
      for (final entry in candidate.commonNames.entries)
        entry.key.name: List<String>.from(entry.value),
    },
  };
}

SearchResult _searchResultFromMessage(Map<String, dynamic> message) {
  final rawCommonNames = Map<String, dynamic>.from(
    (message['commonNames'] as Map? ?? const {}).cast<Object?, Object?>(),
  );
  return SearchResult(
    id: message['id'] as String,
    name: message['name'] as String,
    type: _entityTypeFromName(message['type'] as String),
    commonNames: {
      for (final language in Language.values)
        language: ((rawCommonNames[language.name] as List?) ?? const [])
            .whereType<String>()
            .toList(),
    },
  );
}

_SearchCandidate _candidateFromReferenceRow(
  Map<String, dynamic> row, {
  required String normalizedSearchTerm,
  int sourcePriority = 1,
}) {
  return _SearchCandidate(
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

_SearchCandidate _candidateFromDownloadedRow(
  Map<String, dynamic> row, {
  required String normalizedSearchTerm,
  bool isFallback = false,
}) {
  final entityType = row['entity_type'] as String;
  final entityId = row['entity_id'] as String? ?? row['id'] as String;
  final scientificName = row['scientific_name'] as String;

  return _SearchCandidate(
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

List<_SearchCandidate> _mergeCandidates(List<_SearchCandidate> candidates) {
  final mergedByKey = <String, _SearchCandidate>{};
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

int _compareCandidates(_SearchCandidate a, _SearchCandidate b) {
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

int _localizedCommonNameWeight(_SearchCandidate candidate) {
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
      .map(RuntimeCommonNameSearchRepository.normalizeSearchText)
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

SearchEntityType _entityTypeFromName(String entityType) {
  switch (entityType) {
    case 'species':
      return SearchEntityType.species;
    case 'genus':
      return SearchEntityType.genus;
    case 'family':
      return SearchEntityType.family;
    case 'order':
      return SearchEntityType.order;
    case 'classType':
      return SearchEntityType.classType;
    default:
      throw StateError('Unknown SearchEntityType: $entityType');
  }
}

class _SearchCandidate {
  final String stableKey;
  final String id;
  final String name;
  final Map<Language, List<String>> commonNames;
  final SearchEntityType type;
  final int matchPriority;
  final int sourcePriority;

  const _SearchCandidate({
    required this.stableKey,
    required this.id,
    required this.name,
    required this.commonNames,
    required this.type,
    required this.matchPriority,
    required this.sourcePriority,
  });

  _SearchCandidate merge(_SearchCandidate other) {
    final preferred = sourcePriority <= other.sourcePriority ? this : other;
    final secondary = identical(preferred, this) ? other : this;

    return _SearchCandidate(
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
