import 'dart:async';
import 'dart:convert';

import 'package:discere/external/inaturalist/inat_ancestry_requirement.dart';
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

  group('INatTaxonIdResolver.resolve', () {
    /// Mollusca and Tracheophyta, as iNaturalist numbers them.
    const mollusca = 47115;
    const tracheophyta = 211194;
    const molluscs = INatAncestryRequirement([
      {mollusca},
    ]);

    Map<String, Object> species(
      int id,
      String name, {
      String? matchedTerm,
      List<int> ancestorIds = const [],
    }) => {
      'id': id,
      'name': name,
      'rank': 'species',
      'matched_term': ?matchedTerm,
      'ancestor_ids': ancestorIds,
    };

    test('asks for the ancestor ids of each hit', () async {
      final searches = <Uri>[];
      final resolver = _resolver({
        'results': [species(703, 'Specius alpha')],
      }, searches: searches);

      await resolver.resolve('Specius alpha');

      expect(
        searches.single.queryParameters['fields']?.split(','),
        contains('ancestor_ids'),
      );
      expect(searches.single.queryParametersAll['rank'], ['species']);
    });

    test('accepts a synonym hit', () async {
      final resolver = _resolver({
        'results': [
          species(701, 'Natator depressus', matchedTerm: 'Natator depressa'),
        ],
      });

      expect(await resolver.resolve('Natator depressa'), 701);
    });

    test('does not fall back to the first result', () async {
      final resolver = _resolver({
        'results': [species(702, 'Specius other')],
      });

      await expectLater(
        resolver.resolve('Specius alpha'),
        throwsA(isA<TaxonNotFoundException>()),
      );
    });

    test('takes neither of two taxa carrying the name', () async {
      final resolver = _resolver({
        'results': [
          species(704, 'Triphora pusilla'),
          species(705, 'Triphora pusilla'),
        ],
      });

      await expectLater(
        resolver.resolve('Triphora pusilla'),
        throwsA(isA<TaxonNotFoundException>()),
      );
    });

    test('takes a hit under an allowed phylum', () async {
      final resolver = _resolver({
        'results': [
          species(706, 'Triphora pusilla', ancestorIds: [1, mollusca, 706]),
        ],
      });

      expect(
        await resolver.resolve('Triphora pusilla', ancestry: molluscs),
        706,
      );
    });

    test('takes no hit of another phylum: the orchid is no snail', () async {
      final resolver = _resolver({
        'results': [
          species(
            1217363,
            'Triphora pusilla',
            ancestorIds: [48460, 47126, tracheophyta, 1217363],
          ),
        ],
      });

      await expectLater(
        resolver.resolve('Triphora pusilla', ancestry: molluscs),
        throwsA(isA<TaxonNotFoundException>()),
      );
    });

    test('takes no synonym hit of another phylum', () async {
      final resolver = _resolver({
        'results': [
          species(
            1347697,
            'Paratenuisentis ambiguus',
            matchedTerm: 'Ebalia ambiguus',
            ancestorIds: [1, 48920, 1347697],
          ),
        ],
      });

      await expectLater(
        resolver.resolve('Ebalia ambiguus', ancestry: molluscs),
        throwsA(isA<TaxonNotFoundException>()),
      );
    });

    test('takes the one fitting taxon among homonyms of other phyla', () async {
      final resolver = _resolver({
        'results': [
          species(
            1217363,
            'Triphora pusilla',
            ancestorIds: [tracheophyta, 1217363],
          ),
          species(706, 'Triphora pusilla', ancestorIds: [mollusca, 706]),
        ],
      });

      expect(
        await resolver.resolve('Triphora pusilla', ancestry: molluscs),
        706,
      );
    });

    test('takes a fitting synonym hit when the name itself only hits another '
        'phylum', () async {
      final resolver = _resolver({
        'results': [
          species(
            1217363,
            'Triphora pusilla',
            ancestorIds: [tracheophyta, 1217363],
          ),
          species(
            707,
            'Monophorus pusillus',
            matchedTerm: 'Triphora pusilla',
            ancestorIds: [mollusca, 707],
          ),
        ],
      });

      expect(
        await resolver.resolve('Triphora pusilla', ancestry: molluscs),
        707,
      );
    });

    test('takes nothing when there is nothing to check against', () async {
      final resolver = _resolver({
        'results': [
          species(706, 'Triphora pusilla', ancestorIds: [mollusca, 706]),
        ],
      });

      await expectLater(
        resolver.resolve(
          'Triphora pusilla',
          ancestry: const INatAncestryRequirement([]),
        ),
        throwsA(isA<TaxonNotFoundException>()),
      );
    });

    test('answers null for a failed search, to be retried', () async {
      final resolver = _resolver(const {}, status: 503);

      expect(await resolver.resolve('Triphora pusilla'), isNull);
    });

    test('searches once for the same name, whatever each caller requires', () async {
      final searches = <Uri>[];
      final resolver = _resolver({
        'results': [
          species(706, 'Triphora pusilla', ancestorIds: [mollusca, 706]),
        ],
      }, searches: searches);

      expect(await resolver.resolve('Triphora pusilla'), 706);
      expect(
        await resolver.resolve('Triphora pusilla', ancestry: molluscs),
        706,
      );
      expect(searches, hasLength(1));
    });
  });

  group('INatTaxonIdResolver.resolveExact with an ancestry requirement', () {
    test('takes no exact hit outside the allowed phyla', () async {
      final resolver = _resolver({
        'results': [
          {
            'id': 421750,
            'name': 'Megalomma',
            'rank': 'genus',
            'ancestor_ids': [48460, 1, 47120, 421750],
          },
        ],
      });

      await expectLater(
        resolver.resolveExact(
          'Megalomma',
          rank: 'genus',
          ancestry: const INatAncestryRequirement([
            {47491},
          ]),
        ),
        throwsA(isA<TaxonNotFoundException>()),
      );
    });

    test('takes an exact hit under the allowed phylum', () async {
      final resolver = _resolver({
        'results': [
          {
            'id': 60000,
            'name': 'Megalomma',
            'rank': 'genus',
            'ancestor_ids': [48460, 1, 47491, 60000],
          },
        ],
      });

      expect(
        await resolver.resolveExact(
          'Megalomma',
          rank: 'genus',
          ancestry: const INatAncestryRequirement([
            {47491},
          ]),
        ),
        60000,
      );
    });
  });
}
