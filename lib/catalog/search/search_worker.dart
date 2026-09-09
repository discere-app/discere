import 'dart:async';
import 'dart:isolate';

import 'package:discere/catalog/model/search_result.dart';
import 'package:discere/catalog/search/search_ranking.dart';
import 'package:discere/shared/model/language.dart';

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

  final mergedCandidates = mergeCandidates([
    ...referenceRows.map(
      (row) => candidateFromReferenceRow(
        row,
        normalizedSearchTerm: normalizedSearchTerm,
      ),
    ),
    ...downloadedRows.map(
      (row) => candidateFromDownloadedRow(
        row,
        normalizedSearchTerm: normalizedSearchTerm,
      ),
    ),
    ...fallbackRows.map(
      (row) => candidateFromDownloadedRow(
        row,
        normalizedSearchTerm: normalizedSearchTerm,
        isFallback: true,
      ),
    ),
    ...inatRows.map(
      (row) => candidateFromReferenceRow(
        row,
        normalizedSearchTerm: normalizedSearchTerm,
        sourcePriority: 0,
      ),
    ),
    ...referenceFallbackRows.map(
      (row) => candidateFromReferenceRow(
        row,
        normalizedSearchTerm: normalizedSearchTerm,
        sourcePriority: 2,
      ),
    ),
  ]);

  mergedCandidates.sort(compareCandidates);
  return mergedCandidates.map(_searchResultToMessage).toList();
}

List<Map<String, dynamic>> _messageRows(Object? rawRows) {
  final rows = rawRows as List? ?? const [];
  return rows
      .whereType<Map>()
      .map((row) => Map<String, dynamic>.from(row.cast<Object?, Object?>()))
      .toList();
}

Map<String, dynamic> _searchResultToMessage(SearchCandidate candidate) {
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
