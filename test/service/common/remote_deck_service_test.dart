import 'dart:convert';

import 'package:discere/learning/service/remote_deck_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RemoteDeckService', () {
    test('uses a patient default timeout for Codeberg loading', () {
      final service = RemoteDeckService(client: http.Client());

      expect(service.indexTimeout, const Duration(seconds: 20));
    });

    test('fetches all decks from a single index request', () async {
      var requestCount = 0;
      final mockClient = MockClient((request) async {
        requestCount++;
        expect(
          request.url.toString(),
          'https://codeberg.org/feberle/discere-data/raw/branch/main/data/decks/index.json',
        );
        return http.Response(
          jsonEncode([
            {
              'name': 'Mittelmeer',
              'description': 'Fische im Mittelmeer',
              'speciesNames': ['Salpa salpa'],
            },
            {
              'name': 'Rotes Meer',
              'description': 'Fische im Roten Meer',
              'speciesNames': ['Pterois miles'],
            },
          ]),
          200,
        );
      });

      final service = RemoteDeckService(client: mockClient);
      final decks = await service.fetchRemoteDecks();

      expect(requestCount, 1);
      expect(decks, hasLength(2));
      expect(decks[0].name, 'Mittelmeer');
      expect(decks[1].name, 'Rotes Meer');
    });

    test('skips malformed entries without failing the whole list', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode([
            {'description': 'missing required name field'},
            {'name': 'Valid Deck', 'description': 'ok'},
          ]),
          200,
        );
      });

      final service = RemoteDeckService(client: mockClient);
      final decks = await service.fetchRemoteDecks();

      expect(decks, hasLength(1));
      expect(decks[0].name, 'Valid Deck');
    });
  });
}
