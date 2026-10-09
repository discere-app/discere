import 'dart:async';

import 'package:discere/enrichment/queue/service/inat_enrichment_queue_service.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/learning/decks/edit/inat_enrichment_offer.dart';
import 'package:discere/shared/service/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../../../mocks.mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockINatEnrichmentQueueService enrichmentQueue;
  late MockNotificationService notificationService;
  late Completer<void> baseScheduling;

  /// Which consent each `scheduleDeckEnrichment` call carried, in call order.
  late List<bool> scheduledWithINat;

  setUp(() {
    enrichmentQueue = MockINatEnrichmentQueueService();
    notificationService = MockNotificationService();
    scheduledWithINat = [];
    when(
      notificationService.shouldPromptForPermission(),
    ).thenAnswer((_) async => false);
    // The consent-withheld call stays in flight until the test completes
    // baseScheduling; the opt-in call finishes immediately.
    when(
      enrichmentQueue.scheduleDeckEnrichment(
        any,
        includeINatPhotos: anyNamed('includeINatPhotos'),
        includeCommonNames: anyNamed('includeCommonNames'),
        coverImageUrlsByDeckId: anyNamed('coverImageUrlsByDeckId'),
        unresolvedNamesByDeckId: anyNamed('unresolvedNamesByDeckId'),
        waitForForegroundIdle: anyNamed('waitForForegroundIdle'),
      ),
    ).thenAnswer((invocation) {
      final withINat = invocation.namedArguments[#includeINatPhotos] as bool;
      scheduledWithINat.add(withINat);
      return withINat ? Future.value() : baseScheduling.future;
    });
  });

  Future<void> openOffer(WidgetTester tester) async {
    // Created inside the test body, not in setUp: only then does completing
    // it resume the offer within the test's fake-async zone.
    baseScheduling = Completer<void>();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<INatEnrichmentQueueService>.value(
            value: enrichmentQueue,
          ),
          Provider<NotificationService>.value(value: notificationService),
        ],
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => offerINatEnrichmentForNewSpecies(
                  context,
                  'deck-1',
                  unresolvedNames: const ['Unknown fish'],
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('asks right away, while the reference images are still being '
      'scheduled', (tester) async {
    await openOffer(tester);

    expect(find.byKey(const Key('inat_download_dialog')), findsOneWidget);
    expect(scheduledWithINat, [false]);
    expect(baseScheduling.isCompleted, isFalse);
  });

  testWidgets('schedules the opt-in only once the unresolved names are '
      'queued, so its consent reaches them', (tester) async {
    await openOffer(tester);

    await tester.tap(find.byKey(const Key('inat_download_button')));
    await tester.pumpAndSettle();
    expect(scheduledWithINat, [false]);

    baseScheduling.complete();
    await tester.pumpAndSettle();
    expect(scheduledWithINat, [false, true]);
  });

  testWidgets('declining schedules nothing beyond the reference images', (
    tester,
  ) async {
    await openOffer(tester);

    await tester.tap(find.byKey(const Key('inat_skip_button')));
    await tester.pumpAndSettle();
    baseScheduling.complete();
    await tester.pumpAndSettle();

    expect(scheduledWithINat, [false]);
  });
}
