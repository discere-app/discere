import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:discere/learning/model/create_deck.dart';
import 'package:discere/shared/model/app_exception.dart';

class RemoteDeckService {
  final http.Client _client;
  static const String _baseUrl =
      'https://codeberg.org/api/v1/repos/feberle/discere-data/contents/data/decks?ref=main';

  RemoteDeckService({http.Client? client}) : _client = client ?? http.Client();

  /// Fetches the list of deck metadata from the remote repository.
  Future<List<CreateDeck>> fetchRemoteDecks() async {
    try {
      final response = await _client.get(Uri.parse(_baseUrl));
      if (response.statusCode != 200) {
        throw ServerException(
          'Failed to fetch deck list from server.',
          statusCode: response.statusCode,
        );
      }

      final List<dynamic> contents = jsonDecode(response.body);
      final jsonFiles = contents
          .where(
            (item) => item['type'] == 'file' && item['name'].endsWith('.json'),
          )
          .toList();

      final List<CreateDeck> decks = [];
      for (var file in jsonFiles) {
        try {
          final downloadUrl = file['download_url'] as String;
          final deck = await fetchDeckDetails(downloadUrl);
          decks.add(deck);
        } catch (e) {
          // Log specific deck errors but allow others to load
          debugPrint('Error fetching deck details for ${file['name']}: $e');
        }
      }

      if (decks.isEmpty && jsonFiles.isNotEmpty) {
        throw DataFormatException(
          'Could not load any deck details, even though files were found.',
        );
      }

      return decks;
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

  Future<CreateDeck> fetchDeckDetails(String downloadUrl) async {
    try {
      final response = await _client.get(Uri.parse(downloadUrl));
      if (response.statusCode != 200) {
        throw ServerException(
          'Failed to fetch deck details.',
          statusCode: response.statusCode,
        );
      }

      final jsonText = utf8.decode(response.bodyBytes);
      return CreateDeck.fromJsonString(jsonText);
    } on http.ClientException catch (e) {
      throw NetworkException(
        'Connection failed for $downloadUrl',
        originalError: e,
      );
    } on FormatException catch (e) {
      throw DataFormatException(
        'Invalid JSON format for deck at $downloadUrl',
        originalError: e,
      );
    }
  }
}
