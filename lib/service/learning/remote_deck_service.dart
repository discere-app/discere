import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../model/ui/create_deck.dart';

class RemoteDeckService {
  final http.Client _client;
  static const String _baseUrl = 'https://codeberg.org/api/v1/repos/feberle/discere-data/contents/data/decks?ref=main';

  RemoteDeckService({http.Client? client}) : _client = client ?? http.Client();

  /// Fetches the list of deck metadata from the remote repository.
  /// Note: This fetches the full JSON for each file to provide details for the list view.
  Future<List<CreateDeck>> fetchRemoteDecks() async {
    final response = await _client.get(Uri.parse(_baseUrl));
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch deck list: ${response.statusCode}');
    }

    final List<dynamic> contents = jsonDecode(response.body);
    final jsonFiles = contents
        .where((item) => item['type'] == 'file' && item['name'].endsWith('.json'))
        .toList();

    final List<CreateDeck> decks = [];
    for (var file in jsonFiles) {
      try {
        final downloadUrl = file['download_url'] as String;
        final deck = await fetchDeckDetails(downloadUrl);
        decks.add(deck);
      } catch (e) {
        // Log error and continue with other decks
        if (kDebugMode) {
          print('Error fetching deck details for ${file['name']}: $e');
        }
      }
    }
    return decks;
  }

  Future<CreateDeck> fetchDeckDetails(String downloadUrl) async {
    final response = await _client.get(Uri.parse(downloadUrl));
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch deck details (${response.statusCode})');
    }

    // Use utf8.decode to handle special characters correctly
    final jsonText = utf8.decode(response.bodyBytes);
    return CreateDeck.fromJsonString(jsonText);
  }
}
