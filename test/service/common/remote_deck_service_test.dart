import 'package:discere/learning/service/remote_deck_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RemoteDeckService', () {
    test('uses more patient defaults for Codeberg loading', () {
      final service = RemoteDeckService();

      expect(service.indexTimeout, const Duration(seconds: 20));
      expect(service.deckDetailTimeout, const Duration(seconds: 20));
    });
  });
}
