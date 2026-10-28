/// The online deck catalog this build reads, fetched live from discere-data.
///
/// The app reads the index of its deck format version
/// (`AppConstants.deckCatalogIndexUrl`); one missing or empty there would
/// leave the online tab broken for every user of a release. The release
/// workflow runs this before building. It needs the network and the live
/// state of discere-data, so it sits outside `test/` and runs only when
/// named: `flutter test release_check/`.
library;

import 'dart:io';

import 'package:discere/learning/import/remote_deck_service.dart';
import 'package:discere/shared/util/dev_data_source_override.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  // Reading a deck asks the binding for the platform locale. The test
  // binding answers every HTTP request with 400 to keep unit tests off the
  // network, which is exactly what this check has to reach.
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  test('no development override redirects the catalog URL', () {
    // Under `flutter test` kDebugMode holds, so a committed override would
    // replace the URL checked below.
    expect(devDeckCatalogIndexUrlOverride, isNull);
  });

  test('the catalog index this build reads lists decks', () async {
    final client = http.Client();
    addTearDown(client.close);

    final decks = await RemoteDeckService(client: client).fetchRemoteDecks();

    expect(decks, isNotEmpty);
  });
}
