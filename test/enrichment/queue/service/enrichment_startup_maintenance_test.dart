import 'package:discere/enrichment/pipeline/repository/enrichment_ownership_repository.dart';
import 'package:discere/enrichment/pipeline/repository/enrichment_work_maintenance_repository.dart';
import 'package:discere/enrichment/pipeline/repository/enrichment_work_tables.dart';
import 'package:discere/enrichment/ports/enrichment_job_ports.dart';
import 'package:discere/enrichment/queue/repository/enrichment_job_repository.dart';
import 'package:discere/enrichment/queue/service/enrichment_startup_maintenance.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import '../../../support/in_memory_user_database.dart';
import '../../../support/persisted_warnings.dart';

class _FixedDeckIds implements AllDeckIdsPort {
  final Set<String> deckIds;

  const _FixedDeckIds(this.deckIds);

  @override
  Future<Set<String>> loadAllDeckIds() async => deckIds;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database database;
  late List<String> warnings;
  late EnrichmentStartupMaintenance maintenance;

  setUp(() async {
    warnings = recordPersistedWarnings();
    database = await openInMemoryUserDatabase();
    maintenance = EnrichmentStartupMaintenance(
      maintenanceRepository: EnrichmentWorkMaintenanceRepository(database),
      jobRepository: EnrichmentJobRepository(database),
      ownershipRepository: EnrichmentOwnershipRepository(database),
      allDeckIdsPort: const _FixedDeckIds({'deck-1'}),
    );
  });

  tearDown(() async {
    if (database.isOpen) await database.close();
  });

  test('a repair failing on a real database error lets startup go on and '
      'logs a warning with its stack trace', () async {
    await database.execute('DROP TABLE ${EnrichmentWorkTables.taxonomyWork}');

    await expectLater(maintenance.recoverInterruptedWork(), completes);

    expect(warnings, hasLength(1));
    expect(
      warnings.single,
      startsWith(
        '[EnrichmentStartupMaintenance] Recovering interrupted enrichment '
        'work failed — SqfliteFfiException: ',
      ),
    );
    expect(
      warnings.single,
      contains('no such table: ${EnrichmentWorkTables.taxonomyWork}'),
    );
    expect(warnings.single, contains('\n    #0 '));
  });

  test('a repair is dropped without a warning when the database is closed '
      'underneath it', () async {
    await database.close();

    await expectLater(maintenance.recoverInterruptedWork(), completes);
    await expectLater(maintenance.pruneOrphanedWork(), completes);

    expect(warnings, isEmpty);
  });
}
