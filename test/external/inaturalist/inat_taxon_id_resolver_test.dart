import 'dart:async';
import 'dart:convert';

import 'package:discere/external/inaturalist/inat_api_client.dart';
import 'package:discere/external/inaturalist/inat_taxon_id_resolver.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// What `/v2/taxa?q=Sebastidae&rank=family` answers: no Sebastidae, but
/// Scorpaenidae, which carries it as a synonym.
const _sebastidaeSearch = {
  'results': [
    {
      'id': 47285,
      'name': 'Scorpaenidae',
      'rank': 'family',
      'matched_term': 'Sebastidae',
    },
  ],
};

/// What `/v2/taxa?q=Mollu&rank=family` answers: a plant family that merely
/// starts like the name asked for.
const _molluSearch = {
  'results': [
    {
      'id': 71416,
      'name': 'Molluginaceae',
      'rank': 'family',
      'matched_term': 'Molluginaceae',
    },
  ],
};

/// A resolver over a fake API that answers every taxon search with [body]
/// and [status], counting the searches in [searches].
INatTaxonIdResolver _resolver(
  Object body, {
  int status = 200,
  List<Uri>? searches,
}) {
  final client = MockClient((request) async {
    searches?.add(request.url);
    return http.Response(jsonEncode(body), status);
  });
  return INatTaxonIdResolver(api: INatApiClient(client: client));
}

void main() {
  group('INatTaxonIdResolver.resolveExact', () {
    test('returns the taxon named exactly so on the rank asked for', () async {
      final searches = <Uri>[];
      final resolver = _resolver({
        'results': [
          {'id': 47273, 'name': 'Elasmobranchii', 'rank': 'subclass'},
          {'id': 60450, 'name': 'Holocephali', 'rank': 'class'},
        ],
      }, searches: searches);

      expect(await resolver.resolveExact('holocephali', rank: 'class'), 60450);
      expect(searches.single.queryParametersAll['rank'], ['class']);
    });

    test('does not take a taxon that only matches as a synonym', () async {
      final resolver = _resolver(_sebastidaeSearch);

      await expectLater(
        resolver.resolveExact('Sebastidae', rank: 'family'),
        throwsA(isA<TaxonNotFoundException>()),
      );
    });

    test('does not fall back to the first result', () async {
      final resolver = _resolver(_molluSearch);

      await expectLater(
        resolver.resolveExact('Mollu', rank: 'family'),
        throwsA(isA<TaxonNotFoundException>()),
      );
    });

    test('does not take the exact name on another rank', () async {
      final resolver = _resolver({
        'results': [
          {'id': 47273, 'name': 'Elasmobranchii', 'rank': 'subclass'},
        ],
      });

      await expectLater(
        resolver.resolveExact('Elasmobranchii', rank: 'class'),
        throwsA(isA<TaxonNotFoundException>()),
      );
    });

    test(
      'reports a failed search as a network failure, not as absent',
      () async {
        final resolver = _resolver(const {}, status: 503);

        await expectLater(
          resolver.resolveExact('Holocephali', rank: 'class'),
          throwsA(isA<http.ClientException>()),
        );
      },
    );

    test('reports a timed-out search as such', () {
      fakeAsync((async) {
        final client = MockClient((_) => Completer<http.Response>().future);
        final resolver = INatTaxonIdResolver(
          api: INatApiClient(client: client),
        );

        Object? error;
        resolver
            .resolveExact('Holocephali', rank: 'class')
            .then<void>((_) {}, onError: (Object e) => error = e);
        async.elapse(const Duration(seconds: 11));

        expect(error, isA<TimeoutException>());
      });
    });

    test('is not answered from what a lax species lookup remembered', () async {
      final searches = <Uri>[];
      final resolver = _resolver(_sebastidaeSearch, searches: searches);

      expect(await resolver.resolve('Sebastidae'), 47285);
      await expectLater(
        resolver.resolveExact('Sebastidae', rank: 'family'),
        throwsA(isA<TaxonNotFoundException>()),
      );
      expect(searches, hasLength(2));
    });

    test('remembers an exact answer', () async {
      final searches = <Uri>[];
      final resolver = _resolver({
        'results': [
          {'id': 60450, 'name': 'Holocephali', 'rank': 'class'},
        ],
      }, searches: searches);

      await resolver.resolveExact('Holocephali', rank: 'class');
      await resolver.resolveExact('Holocephali', rank: 'class');

      expect(searches, hasLength(1));
    });
  });

  // Species resolution feeds the photo lookup and deliberately stays lax;
  // pinned here so tightening the higher ranks cannot change it unnoticed.
  group('INatTaxonIdResolver.resolve', () {
    test('accepts a synonym hit', () async {
      final resolver = _resolver({
        'results': [
          {
            'id': 701,
            'name': 'Natator depressus',
            'rank': 'species',
            'matched_term': 'Natator depressa',
          },
        ],
      });

      expect(await resolver.resolve('Natator depressa'), 701);
    });

    test('falls back to the first result', () async {
      final resolver = _resolver({
        'results': [
          {'id': 702, 'name': 'Specius other', 'rank': 'species'},
        ],
      });

      expect(await resolver.resolve('Specius alpha'), 702);
    });

    test('searches on the species rank', () async {
      final searches = <Uri>[];
      final resolver = _resolver({
        'results': [
          {'id': 703, 'name': 'Specius alpha', 'rank': 'species'},
        ],
      }, searches: searches);

      await resolver.resolve('Specius alpha');

      expect(searches.single.queryParametersAll['rank'], ['species']);
    });
  });
}
