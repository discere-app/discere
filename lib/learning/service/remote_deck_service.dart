import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:discere/learning/model/create_deck.dart';
import 'package:discere/shared/model/app_exception.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:discere/learning/service/deck_serialization_worker.dart';

class RemoteDeckService {
  static final _log = Logger.forType(RemoteDeckService);
  static const _timeout = Duration(seconds: 10);
  static const String _baseUrl =
      'https://codeberg.org/api/v1/repos/feberle/discere-data/contents/data/decks?ref=main';

  final http.Client _client;
  final DeckSerializationWorker _serializationWorker;

  RemoteDeckService({
    http.Client? client,
    DeckSerializationWorker? serializationWorker,
  }) : _client = client ?? http.Client(),
       _serializationWorker =
           serializationWorker ?? const DeckSerializationWorker();

  /// Fetches the list of deck metadata from the remote repository.
  /// Deck details are loaded in parallel for speed.
  Future<List<CreateDeck>> fetchRemoteDecks() async {
    try {
      _log.debug('Fetching remote deck index');
      final response = await _client.get(Uri.parse(_baseUrl)).timeout(_timeout);

      if (response.statusCode != 200) {
        throw ServerException(
          'Failed to fetch deck list from server.',
          statusCode: response.statusCode,
        );
      }

      final contents =
          await _serializationWorker.decodeJsonBytes(response.bodyBytes)
              as List<dynamic>;
      final downloadUrls = contents
          .where(
            (item) => item['type'] == 'file' && item['name'].endsWith('.json'),
          )
          .map((item) => item['download_url'] as String)
          .toList();

      // Fetch all deck details in parallel
      final results = await Future.wait(
        downloadUrls.map((url) => _fetchDeckDetails(url)),
      );

      final decks = results.whereType<CreateDeck>().toList();

      if (decks.isEmpty && downloadUrls.isNotEmpty) {
        throw DataFormatException(
          'Could not load any deck details, even though files were found.',
        );
      }

      return decks;
    } on TimeoutException {
      throw NetworkException(
        'Server did not respond within ${_timeout.inSeconds}s.',
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

  /// Returns null on failure so a single bad file doesn't break the whole list.
  Future<CreateDeck?> _fetchDeckDetails(String downloadUrl) async {
    try {
      final response = await _client
          .get(Uri.parse(downloadUrl))
          .timeout(_timeout);

      if (response.statusCode != 200) {
        _log.warn('Failed to fetch $downloadUrl (${response.statusCode})');
        return null;
      }

      return _serializationWorker.decodeCreateDeckBytes(response.bodyBytes);
    } catch (e) {
      _log.warn('Error fetching deck from $downloadUrl: $e');
      return null;
    }
  }
}
