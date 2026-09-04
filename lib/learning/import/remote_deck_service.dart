import 'dart:async';
import 'dart:io';

import 'package:discere/learning/model/create_deck.dart';
import 'package:discere/learning/service/deck_serialization_worker.dart';
import 'package:discere/shared/model/app_exception.dart';
import 'package:discere/shared/util/constants.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class RemoteDeckService {
  static final _log = Logger.forType(RemoteDeckService);
  static const _defaultIndexTimeout = Duration(seconds: 20);
  static const String _indexUrl = AppConstants.deckCatalogIndexUrl;

  final http.Client _client;
  final DeckSerializationWorker _serializationWorker;
  final Duration _indexTimeout;

  RemoteDeckService({
    required http.Client client,
    DeckSerializationWorker? serializationWorker,
    Duration indexTimeout = _defaultIndexTimeout,
  }) : _client = client,
       _indexTimeout = indexTimeout,
       _serializationWorker =
           serializationWorker ?? const DeckSerializationWorker();

  @visibleForTesting
  Duration get indexTimeout => _indexTimeout;

  /// Fetches the list of deck metadata from the remote repository's combined
  /// index file (a single request instead of one listing + one-per-deck).
  Future<List<CreateDeck>> fetchRemoteDecks() async {
    try {
      _log.debug('Fetching remote deck index');
      final response = await _client
          .get(Uri.parse(_indexUrl))
          .timeout(_indexTimeout);

      if (response.statusCode != 200) {
        throw ServerException(
          'Failed to fetch deck list from server.',
          statusCode: response.statusCode,
        );
      }

      final entries =
          await _serializationWorker.decodeJsonBytes(response.bodyBytes)
              as List<dynamic>;

      final decks = <CreateDeck>[];
      for (final entry in entries) {
        try {
          final map = Map<String, dynamic>.from(
            (entry as Map).cast<Object?, Object?>(),
          );
          decks.add(CreateDeck.fromJson(map));
        } catch (e) {
          // A single malformed entry shouldn't break the whole list.
          _log.warn('Skipping malformed deck entry in index: $e');
        }
      }

      if (decks.isEmpty && entries.isNotEmpty) {
        throw DataFormatException(
          'Could not load any deck details, even though entries were found.',
        );
      }

      return decks;
    } on TimeoutException {
      throw NetworkException(
        'Server did not respond within ${_indexTimeout.inSeconds}s.',
      );
    } on http.ClientException catch (e) {
      throw NetworkException(
        'Network connection failed while fetching decks.',
        originalError: e,
      );
    } on SocketException catch (e) {
      throw NetworkException(
        'No internet connection or server unreachable.',
        originalError: e,
      );
    } on FormatException catch (e) {
      throw DataFormatException(
        'Invalid response format from server.',
        originalError: e,
      );
    } catch (e) {
      if (e is AppException) rethrow;
      throw AppException(
        'An unexpected error occurred while fetching decks.',
        originalError: e,
      );
    }
  }
}
