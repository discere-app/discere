import 'package:flutter_test/flutter_test.dart';
import 'package:discere/catalog/repository/species_repository.dart';
import 'test_utils.dart';

void main() {
  initializeIntegrationTest();

  setUp(() async {
    await resetTestState();
  });

  testWidgets(
    'SpeciesRepository handles large queries requiring chunking (> 500 species)',
    (WidgetTester tester) async {
      final repository = SpeciesRepository();

      // Generate 600 valid tuples (1200 parameters total).
      // The SQLite limit is 999 parameters. Without chunking, this would definitely crash.
      final largeList = List.generate(
        600,
        (i) => ('DummyGenus$i', 'dummySpecies$i'),
      );

      // Running this proves our chunking safely avoids the PlatformException.
      final result = await repository.getSpeciesIdsByScientificNames(largeList);

      // They are dummy names so we expect nothing back, but the crucial part is it didn't crash.
      expect(result, isEmpty);

      // Same for the other chunking fix we added
      final largeIds = List.generate(1200, (i) => 'dummy-id-$i').toSet();
      final speciesResult = await repository.getSpecies(largeIds);
      expect(speciesResult, isEmpty);
    },
    timeout: integrationTestTimeout,
  );
}
