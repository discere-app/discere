import 'package:discere/app/util/reference_db_sources.dart';
import 'package:discere/catalog/service/source_service.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../../mocks.mocks.dart';
import '../../support/in_memory_user_database.dart';
import '../diagnostics/diagnostics_page_data_fixture.dart';

void main() {
  const log = ScopedLogger('reference_db_sources_test');
  late MockSourceRepository repository;
  late SourceService service;
  late List<({LogLevel level, String scope})> warnings;

  setUp(() {
    repository = MockSourceRepository();
    service = SourceService(repository);
    warnings = [];
    Logger.configurePersistence(
      enabled: true,
      sink: (level, scope, message) async {
        warnings.add((level: level, scope: scope));
      },
    );
  });

  tearDown(() => Logger.configurePersistence(enabled: false));

  test('keeps the reference database sources that name a release, in '
      'their order, and none of the synthetic ones', () async {
    when(repository.findAll()).thenAnswer(
      (_) async => [
        referenceDbSource('fishbase', 'FishBase', version: 'v26.07'),
        referenceDbSource('sealifebase', 'SeaLifeBase', version: 'v26.04'),
        referenceDbSource('worms', 'WoRMS', version: ''),
        referenceDbSource('gbif', 'GBIF'),
      ],
    );

    final sources = await loadReferenceDbSources(service, log);

    expect(sources.map((source) => source.id), ['fishbase', 'sealifebase']);
  });

  test('answers none when the database cannot be read, and logs it as a '
      'warning', () async {
    when(repository.findAll()).thenThrow(StateError('no reference db'));

    expect(await loadReferenceDbSources(service, log), isEmpty);
    expect(warnings, [(level: LogLevel.warning, scope: log.scope)]);
  });

  test('answers none for a database closed underneath the call by a '
      'restart, without a warning', () async {
    final closed = await closedDatabaseException();
    when(repository.findAll()).thenThrow(closed);

    expect(await loadReferenceDbSources(service, log), isEmpty);
    expect(warnings, isEmpty);
  });
}
