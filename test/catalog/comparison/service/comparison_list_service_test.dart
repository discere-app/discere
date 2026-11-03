import 'dart:async';

import 'package:discere/catalog/comparison/repository/comparison_list_repository.dart';
import 'package:discere/catalog/comparison/service/comparison_list_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import '../../../support/in_memory_user_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late ComparisonListRepository repository;

  setUp(() async {
    db = await openInMemoryUserDatabase();
    repository = ComparisonListRepository(database: db);
  });

  tearDown(() => db.close());

  /// Completes with [service]'s next notification.
  Future<void> nextNotification(ComparisonListService service) {
    final notified = Completer<void>();
    void onNotified() {
      service.removeListener(onNotified);
      notified.complete();
    }

    service.addListener(onNotified);
    return notified.future;
  }

  /// A service whose first load has finished, counting its notifications
  /// from then on.
  Future<(ComparisonListService, List<void>)> loadedService() async {
    final service = ComparisonListService(repository);
    await nextNotification(service);
    final notifications = <void>[];
    service.addListener(() => notifications.add(null));
    return (service, notifications);
  }

  test('loads the stored lists on construction', () async {
    await repository.createList(
      id: 'l1',
      name: 'Rays',
      speciesIds: {'sp-a'},
      at: DateTime(2026, 11, 2),
    );

    final (service, _) = await loadedService();

    expect(service.lists!.single.name, 'Rays');
    expect(service.listById('l1')!.speciesIds, ['sp-a']);
    expect(service.loadError, isNull);
  });

  test('every change is stored and told to its listeners with the new '
      'state', () async {
    final (service, notifications) = await loadedService();
    expect(service.lists, isEmpty);

    await service.createList('Rays', {'sp-a', 'sp-b'});
    expect(notifications, hasLength(1));
    final id = service.lists!.single.id;
    expect(service.listById(id)!.speciesIds, ['sp-a', 'sp-b']);

    await service.addSpecies(id, {'sp-c'});
    expect(notifications, hasLength(2));
    expect(service.listById(id)!.speciesIds, ['sp-a', 'sp-b', 'sp-c']);

    await service.removeSpecies(id, 'sp-a');
    expect(notifications, hasLength(3));
    expect(service.listById(id)!.speciesIds, ['sp-b', 'sp-c']);

    await service.renameList(id, 'Stingrays');
    expect(notifications, hasLength(4));
    expect(service.listById(id)!.name, 'Stingrays');

    await service.deleteList(id);
    expect(notifications, hasLength(5));
    expect(service.listById(id), isNull);
    expect(await repository.getLists(), isEmpty);
  });

  test('a failed load is reported and leaves the lists unloaded', () async {
    await db.close();

    final service = ComparisonListService(repository);
    await nextNotification(service);

    expect(service.loadError, isNotNull);
    expect(service.lists, isNull);
  });
}
