import 'dart:async';

import 'package:discere/app/bootstrap/app_session.dart';
import 'package:discere/diagnostics/repository/local_diagnostics_repository.dart';
import 'package:discere/diagnostics/service/local_diagnostics.dart';
import 'package:discere/learning/service/deck_update_service.dart';
import 'package:discere/shared/persistence/user_data_writes.dart';
import 'package:discere/shared/service/network_availability.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../mocks.mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockNotificationService notifications;
  late MockINatEnrichmentQueueService enrichmentQueue;
  late AppSession session;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    notifications = MockNotificationService();
    when(notifications.dispose()).thenAnswer((_) async {});
    enrichmentQueue = MockINatEnrichmentQueueService();
    when(enrichmentQueue.shutdown()).thenAnswer((_) async {});
    final deckRepository = MockDeckRepository();
    final remoteDeckService = MockRemoteDeckService();
    session = AppSession(
      notificationService: notifications,
      enrichmentQueue: enrichmentQueue,
      deckRepository: deckRepository,
      remoteDeckService: remoteDeckService,
      deckUpdateService: DeckUpdateService(
        deckRepository,
        remoteDeckService,
        await SharedPreferences.getInstance(),
      ),
      networkAvailability: ConnectivityNetworkAvailability(),
      localDiagnostics: LocalDiagnostics(
        repository: const LocalDiagnosticsRepository(),
        enabled: false,
      ),
      userDataWrites: UserDataWrites(),
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

  test('stopping the session closes its notification service and shuts the '
      'enrichment queue down', () async {
    await session.stop();

    verify(notifications.dispose()).called(1);
    verify(enrichmentQueue.shutdown()).called(1);
  });
}
