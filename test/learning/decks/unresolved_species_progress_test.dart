import 'dart:io';

import 'package:discere/catalog/repository/deprecated_species_name_repository.dart';
import 'package:discere/catalog/repository/species_repository.dart';
import 'package:discere/enrichment/media/service/species_media_service.dart';
import 'package:discere/enrichment/queue/service/inat_enrichment_queue_service.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/learning/decks/edit/edit_deck_page.dart';
import 'package:discere/learning/decks/service/deck_update_applier.dart';
import 'package:discere/learning/model/base_deck.dart';
import 'package:discere/learning/model/create_deck.dart';
import 'package:discere/learning/model/deck_config.dart';
import 'package:discere/learning/model/flashcard_stat.dart';
import 'package:discere/learning/repository/deck_config_repository.dart';
import 'package:discere/learning/repository/deck_repository.dart';
import 'package:discere/learning/repository/flashcard_stat_repository.dart';
import 'package:discere/learning/service/deck_lifecycle_observer.dart';
import 'package:discere/learning/service/decks_service.dart';
import 'package:discere/learning/service/flashcard_service.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/persistence/user_data_writes.dart';
import 'package:discere/shared/service/image_service.dart';
import 'package:discere/shared/service/notification_service.dart';
import 'package:discere/shared/service/user_preferences_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../mocks.mocks.dart';
import '../../support/in_memory_user_database.dart';
import 'edit/edit_deck_manual_enrichment_test.dart'
    show TestINatEnrichmentQueueService;

/// A deck can hold species the reference database does not resolve — after
/// a failed alias migration, or a species a release dropped. Nothing that
/// reads the deck's species sees them, so no save may treat them as
/// removed: their learning progress has to survive editing the deck and
/// applying a deck update.
///
/// Real databases throughout: the reference fixture and an in-memory user
/// database, with the clownfish resolvable and one card under an ID the
/// reference database does not know.
const _deckId = 'deck-1';
const _clownfish = 'discere:species:6002';
const _unresolved = 'discere:fishbase_species:999999';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory tempDir;
  late Database referenceDb;
  late Database userDb;
  late FlashcardStatRepository stats;
  late DecksService decksService;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('unresolved_progress');
    final path = p.join(tempDir.path, 'reference.db');
    await File('test/fixtures/discere_reference_test.db').copy(path);
    referenceDb = await databaseFactoryFfi.openDatabase(path);
    // The edit page would otherwise load the pictures over the network.
    await referenceDb.delete('pictures');
    userDb = await openInMemoryUserDatabase();
    stats = FlashcardStatRepository(database: userDb);
    decksService = DecksService(
      DeckRepository(database: userDb),
      stats,
      SpeciesRepository(database: referenceDb, userDatabase: userDb),
      MockImageService(),
      deckConfigRepository: DeckConfigRepository(database: userDb),
      lifecycleObserver: const NoopDeckLifecycleObserver(),
      userDataWrites: UserDataWrites(),
    );
    await userDb.insert('decks', {
      'id': _deckId,
      'name': 'Reef',
      'description': '',
    });
    await stats.insertOrUpdateFlashcardStats({
      FlashcardStat(speciesId: _clownfish, deckId: _deckId),
      FlashcardStat(speciesId: _unresolved, deckId: _deckId, stability: 7.5),
    });
  });

  tearDown(() async {
    await userDb.close();
    await referenceDb.close();
    await tempDir.delete(recursive: true);
  });

  Future<double?> unresolvedStability() async =>
      (await stats.getFlashcardStat(_unresolved, _deckId))?.stability;

  test('applying a deck update keeps the progress of a species the '
      'reference database does not resolve', () async {
    final applier = DeckUpdateApplier(
      decksService,
      SpeciesRepository(database: referenceDb, userDatabase: userDb),
      deprecatedNames: DeprecatedSpeciesNameRepository(database: referenceDb),
      userDataWrites: UserDataWrites(),
    );
    final remote = CreateDeck(
      name: 'Reef',
      description: '',
      speciesNames: {'Amphiprion ocellaris', 'Prionace glauca'},
    );

    final diff = await applier.diff(_deckId, remote);
    await applier.apply(
      deckId: _deckId,
      remote: remote,
      diff: diff,
      includeAdditions: true,
      includeRemovals: true,
    );

    expect(await unresolvedStability(), 7.5);
    expect(
      await stats.getSpeciesIdsByDeckId(_deckId),
      {_clownfish, _unresolved, 'discere:species:834'},
    );
  });

  testWidgets('saving the deck from the edit page keeps the progress of a '
      'species the reference database does not resolve', (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final stability = await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({
        'has_seen_edit_deck_tutorial': true,
      });
      final preferences = UserPreferencesService(
        await SharedPreferences.getInstance(),
      );
      final flashcardService = MockFlashcardService();
      when(flashcardService.getDeckConfig(any)).thenAnswer(
        (_) async => const DeckConfig(deckId: _deckId, desiredRetention: 0.9),
      );
      when(flashcardService.saveDeckConfig(any)).thenAnswer((_) async {});
      final notifications = MockNotificationService();
      when(
        notifications.shouldPromptForPermission(),
      ).thenAnswer((_) async => false);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<DecksService>.value(value: decksService),
            Provider<ImageService>.value(value: MockImageService()),
            Provider<NotificationService>.value(value: notifications),
            Provider<FlashcardService>.value(value: flashcardService),
            Provider<UserDataWrites>.value(value: UserDataWrites()),
            Provider<SpeciesMediaService>.value(
              value: MockSpeciesMediaService(),
            ),
            ChangeNotifierProvider<INatEnrichmentQueueService>.value(
              value: TestINatEnrichmentQueueService(),
            ),
            ChangeNotifierProvider<UserPreferencesService>.value(
              value: preferences,
            ),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: EditDeckPage(
              deck: BaseDeck(
                id: _deckId,
                name: 'Reef',
                description: '',
                language: Language.en,
              ),
              buildSpeciesDetailPage: (_, _) => const SizedBox.shrink(),
            ),
          ),
        ),
      );
      final nameField = find.byKey(const Key('edit_deck_name_field'));
      for (var i = 0; i < 100 && nameField.evaluate().isEmpty; i++) {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      await tester.enterText(nameField, 'Reef renamed');
      await tester.pump();
      await tester.tap(find.byKey(const Key('edit_deck_save_button')));
      for (var i = 0; i < 20; i++) {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      final deck = (await DeckRepository(
        database: userDb,
      ).getDecksByIds({_deckId})).single;
      expect(deck.name, 'Reef renamed', reason: 'the save went through');
      return unresolvedStability();
    });

    expect(stability, 7.5);
  });
}
