import 'dart:convert';

import 'package:discere/external/inaturalist/inat_taxon_detail_reader.dart';
import 'package:flutter_test/flutter_test.dart';

/// Excerpts of real `/v2/taxa/<id>` answers with
/// `ancestors {id, name, rank}` requested, root first as iNaturalist sends
/// them.
const _greatWhiteShark = '''
{
  "id": 50873, "name": "Carcharodon carcharias", "rank": "species",
  "ancestors": [
    {"id": 1, "name": "Animalia", "rank": "kingdom"},
    {"id": 2, "name": "Chordata", "rank": "phylum"},
    {"id": 355675, "name": "Vertebrata", "rank": "subphylum"},
    {"id": 196614, "name": "Chondrichthyes", "rank": "class"},
    {"id": 47273, "name": "Elasmobranchii", "rank": "subclass"},
    {"id": 551307, "name": "Selachii", "rank": "infraclass"},
    {"id": 551308, "name": "Galeomorphi", "rank": "superorder"},
    {"id": 50870, "name": "Lamniformes", "rank": "order"},
    {"id": 50874, "name": "Lamnidae", "rank": "family"},
    {"id": 50875, "name": "Carcharodon", "rank": "genus"}
  ]
}
''';

/// A brachiopod: the reference data files it under the class Articulata,
/// a name iNaturalist gives a crinoid subclass instead.
const _brachiopod = '''
{
  "id": 469358, "name": "Terebratulina retusa", "rank": "species",
  "ancestors": [
    {"id": 1, "name": "Animalia", "rank": "kingdom"},
    {"id": 122158, "name": "Brachiopoda", "rank": "phylum"},
    {"id": 551549, "name": "Rhynchonelliformea", "rank": "subphylum"},
    {"id": 122159, "name": "Rhynchonellata", "rank": "class"},
    {"id": 122160, "name": "Terebratulida", "rank": "order"},
    {"id": 1066626, "name": "Terebratulidina", "rank": "suborder"},
    {"id": 1066681, "name": "Cancellothyridoidea", "rank": "superfamily"},
    {"id": 192684, "name": "Cancellothyrididae", "rank": "family"},
    {"id": 1067147, "name": "Cancellothyridinae", "rank": "subfamily"},
    {"id": 192685, "name": "Terebratulina", "rank": "genus"}
  ]
}
''';

Map<String, dynamic> _taxon(String json) =>
    jsonDecode(json) as Map<String, dynamic>;

/// A species whose ancestry carries [name] on each of [ranks], ids 1, 2, …
Map<String, dynamic> _withAncestors(String name, List<String> ranks) => {
  'id': 999,
  'ancestors': [
    for (final (index, rank) in ranks.indexed)
      {'id': index + 1, 'name': name, 'rank': rank},
  ],
};

void main() {
  group('ancestorIdNamed', () {
    test('finds a taxon iNaturalist files on another rank', () {
      expect(
        ancestorIdNamed(
          _taxon(_greatWhiteShark),
          scientificName: 'Elasmobranchii',
          rank: 'class',
        ),
        47273,
      );
    });

    test('finds a taxon on the rank asked for', () {
      expect(
        ancestorIdNamed(
          _taxon(_greatWhiteShark),
          scientificName: 'Lamnidae',
          rank: 'family',
        ),
        50874,
      );
    });

    test('does not match a homonym outside the species\' own ancestry', () {
      expect(
        ancestorIdNamed(
          _taxon(_brachiopod),
          scientificName: 'Articulata',
          rank: 'class',
        ),
        isNull,
      );
    });

    test('has no answer for a name absent from the ancestry', () {
      expect(
        ancestorIdNamed(
          _taxon(_greatWhiteShark),
          scientificName: 'Teleostei',
          rank: 'class',
        ),
        isNull,
      );
    });

    test('prefers the rank asked for over the same name on another rank', () {
      // A subgenus named like its genus: asked for the genus, the genus wins
      // whichever of the two comes first.
      final ancestry = _withAncestors('Conus', ['subgenus', 'genus']);

      expect(
        ancestorIdNamed(ancestry, scientificName: 'Conus', rank: 'genus'),
        2,
      );
    });

    test('takes nothing when the name sits on several other ranks', () {
      final ancestry = _withAncestors('Conus', ['genus', 'subgenus']);

      expect(
        ancestorIdNamed(ancestry, scientificName: 'Conus', rank: 'family'),
        isNull,
      );
    });

    test('compares names regardless of case and surrounding space', () {
      expect(
        ancestorIdNamed(
          _taxon(_greatWhiteShark),
          scientificName: ' elasmobranchii ',
          rank: 'class',
        ),
        47273,
      );
    });

    test('has no answer for a taxon without ancestry', () {
      expect(
        ancestorIdNamed(null, scientificName: 'Lamnidae', rank: 'family'),
        isNull,
      );
      expect(
        ancestorIdNamed(
          const {'id': 1},
          scientificName: 'Lamnidae',
          rank: 'family',
        ),
        isNull,
      );
    });
  });
}
