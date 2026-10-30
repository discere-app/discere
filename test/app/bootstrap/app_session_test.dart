import 'dart:async';

import 'package:discere/app/bootstrap/app_session.dart';
import 'package:discere/app/wiring/shared_wiring.dart';
import 'package:discere/catalog/search/search_worker.dart';
import 'package:discere/diagnostics/repository/local_diagnostics_repository.dart';
import 'package:discere/diagnostics/service/local_diagnostics.dart';
import 'package:discere/learning/service/deck_update_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../mocks.mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockNotificationService notifications;
  late MockINatEnrichmentQueueService enrichmentQueue;
  late _RecordingSearchWorker searchWorker;
  late AppSession session;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    notifications = MockNotificationService();
    when(notifications.dispose()).thenAnswer((_) async {});
    enrichmentQueue = MockINatEnrichmentQueueService();
    when(enrichmentQueue.shutdown()).thenAnswer((_) async {});
    final deckRepository = MockDeckRepository();
    final remoteDeckService = MockRemoteDeckService();
    final localDiagnostics = LocalDiagnostics(
      repository: const LocalDiagnosticsRepository(),
      enabled: false,
    );
    searchWorker = _RecordingSearchWorker();
    session = AppSession(
      notificationService: notifications,
      enrichmentQueue: enrichmentQueue,
      deckRepository: deckRepository,
      remoteDeckService: remoteDeckService,
      deckUpdateService: DeckUpdateService(deckRepository, remoteDeckService),
      shared: buildSharedServices(
        sharedPreferences: await SharedPreferences.getInstance(),
        diagnostics: localDiagnostics,
      ),
      searchWorker: searchWorker,
      localDiagnostics: localDiagnostics,
    );
  });

  test('a second restart request while the first runs gets the first '
      'restart instead of starting another', () async {
    final release = Completer<String>();
    var started = 0;
    final first = session.restartOnce(() {
      started++;
      return release.future;
    });
    final second = session.restartOnce(() async {
      started++;
      return 'second';
    });

    release.complete('first');
    expect(await first, 'first');
    expect(await second, 'first');
    expect(started, 1);
  });

  test('stopping the session closes its notification service, shuts the '
      'enrichment queue down and ends the search isolate', () async {
    await session.stop();

    verify(notifications.dispose()).called(1);
    verify(enrichmentQueue.shutdown()).called(1);
    expect(searchWorker.disposeCalls, 1);
  });
}

class _RecordingSearchWorker extends SearchWorker {
  var disposeCalls = 0;

  @override
  Future<void> dispose() async {
    disposeCalls++;
    await super.dispose();
  }
}
