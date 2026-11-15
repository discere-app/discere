import 'package:discere/catalog/search/search_worker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late SearchWorker worker;

  setUp(() => worker = SearchWorker());
  tearDown(() => worker.dispose());

  Map<String, dynamic> speciesRow(String id, String scientificName) => {
    'id': id,
    'scientific_name': scientificName,
    'entity_type': 'species',
  };

  test('a synonym hit carries its synonym across the isolate, a direct hit '
      'none', () async {
    final response = await worker.process(
      SearchWorkerRequest(
        generation: 1,
        normalizedSearchTerm: 'conus coronatus',
        referenceRows: [speciesRow('species:direct', 'Conus coronatus')],
        synonymRows: [
          {
            ...speciesRow('species:synonym', 'Pygmaeconus papalis'),
            'matched_synonym': 'Conus coronatus',
          },
        ],
      ),
    );

    expect(
      response.results.map((result) => (result.id, result.matchedSynonym)),
      [('species:direct', null), ('species:synonym', 'Conus coronatus')],
    );
  });
}
