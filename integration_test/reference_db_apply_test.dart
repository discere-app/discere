import 'dart:io';

import 'package:discere/app/bootstrap/app_session.dart';
import 'package:discere/app/bootstrap/bootstrap_error_shell.dart';
import 'package:discere/app/bootstrap/reference_db_download_error_shell.dart';
import 'package:discere/app/flashcard_app.dart';
import 'package:discere/app/main_screen/main_screen_page.dart';
import 'package:discere/l10n/app_localizations.dart';
import 'package:discere/learning/model/create_deck.dart';
import 'package:discere/learning/model/flashcard_stat.dart';
import 'package:discere/learning/repository/flashcard_stat_repository.dart';
import 'package:discere/learning/service/decks_service.dart';
import 'package:discere/shared/persistence/database_helper.dart';
import 'package:discere/shared/persistence/reference_database_provisioner.dart';
import 'package:discere/shared/persistence/reference_db_downloader.dart';
import 'package:discere/shared/persistence/staged_reference_db.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';

import 'test_utils.dart';

// Applying a reference-DB update found during a session, end to end on a
// device: the update is downloaded and staged next to the active file, the
// notice offers to apply it, and applying restarts the app from inside —
// the bootstrap renames the staged file over the one the ended session had
// open, drops that file's -wal/-shm, and rewrites the user data through the
// new file's entity_aliases. Every step has host tests; what only a device
// shows is the rename under the handles sqflite holds on the active file and
// the restart through the real widget tree.
//
// The update is the fixture with one merge applied (see
// _prepareMergedFixture): species A is gone and aliased to species B, as a
// release does when two entities turn out to be one. The user data sits on
// A before the update and has to sit on B after it.
//
// The update has to arrive through the downloader, not as files laid out
// before startApp: a staging already there when the app starts is installed
// silently by the first bootstrap, and the notice never shows.

/// Sphyrna mokarran, merged away by the update.
const _speciesA = 'discere:species:849';

/// Sphyrna lewini, which the update aliases [_speciesA] to. Not in the deck,
/// so the rewrite has no collision to resolve.
const _speciesB = 'discere:species:847';

const _markerKey = 'reference_db_apply_test_marker';
const _markerValue = 'merged-fixture-v2';

/// Reports version 2 and "downloads" it by writing the merged fixture to
/// where the provisioner stages it. Counts the manifest checks: the
/// bootstrap makes one per run (the background update check of its fast
/// path), which is what tells how often it ran.
class _MergedFixtureDownloader implements ReferenceDbDownloader {
  int manifestFetches = 0;

  @override
  Future<ReferenceDbManifest> fetchManifest() async {
    manifestFetches++;
    return const ReferenceDbManifest(
      version: 2,
      schemaVersion: 2,
      url: 'https://example.invalid/reference.db.gz',
      sha256: '',
      compressedSizeBytes: 1024,
    );
  }

  @override
  Future<void> downloadAndInstall(
    ReferenceDbManifest manifest,
    String destinationPath, {
    required void Function(double progress)? onProgress,
  }) => _prepareMergedFixture(destinationPath);
}

/// Writes the fixture to [path] and merges [_speciesA] into [_speciesB] the
/// way a release does: A is no longer an entity, every alias that pointed
/// at A points at B, and A itself becomes an alias of B — the build
/// invariant ReferenceAliasMap relies on (no alias is an entity, every alias
/// points at one). A's dependent rows go with it, and the full-text indexes
/// over the changed tables are rebuilt, so nothing the app reads still
/// finds A.
///
/// Plus a [_markerKey] row only this copy has, for telling the two files
/// apart through the app's own connection.
Future<void> _prepareMergedFixture(String path) async {
  final data = await rootBundle.load('test/fixtures/discere_reference_test.db');
  await File(path).writeAsBytes(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    flush: true,
  );
  // Its own connection: DatabaseHelper's is the active file's, read-only.
  final db = await openDatabase(path, singleInstance: false);
  try {
    await db.transaction((txn) async {
      for (final table in const [
        'common_names',
        'entity_external_ids',
        'entity_source_keys',
        'taxonomy_distribution_regions',
        'taxonomy_traits',
      ]) {
        await txn.delete(table, where: 'entity_id = ?', whereArgs: [_speciesA]);
      }
      for (final table in const [
        'species_name_lookup',
        'species_scientific_names',
      ]) {
        await txn.delete(
          table,
          where: 'species_id = ?',
          whereArgs: [_speciesA],
        );
      }
      await txn.delete(
        'pictures',
        where: 'species = ?',
        whereArgs: [_speciesA],
      );
      await txn.delete('species', where: 'id = ?', whereArgs: [_speciesA]);
      await txn.update(
        'entity_aliases',
        {'entity_id': _speciesB},
        where: 'entity_id = ?',
        whereArgs: [_speciesA],
      );
      await txn.insert('entity_aliases', {
        'alias_id': _speciesA,
        'entity_id': _speciesB,
      });
      for (final fts in const ['species_fts', 'common_names_fts']) {
        await txn.execute("INSERT INTO $fts($fts) VALUES('rebuild')");
      }
      await txn.insert('metadata', {'key': _markerKey, 'value': _markerValue});
    });
    // Into the main file: only that one is renamed into place.
    await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
  } finally {
    await db.close();
  }
}

/// A deck holding only [_speciesA], with a reviewed card on it.
///
/// The deck goes through DecksService, the path every deck-creating flow
/// takes. The learning state is written through the repository instead of
/// by reviewing the card: reaching a graded card through the review UI is a
/// session of its own, and this test is about where the row ends up, which
/// a known stability and review date pin down exactly.
Future<String> _seedUserDataOnSpeciesA(BuildContext context) async {
  final decksService = Provider.of<DecksService>(context, listen: false);
  final deckId = await decksService.createDeck(
    CreateDeck(
      name: 'Hammerhead deck',
      description: '',
      speciesIds: const {_speciesA},
    ),
  );
  await FlashcardStatRepository().insertOrUpdateFlashcardStats({
    FlashcardStat(
      speciesId: _speciesA,
      deckId: deckId,
      stability: 7.5,
      difficulty: 4.2,
      lastReviewDate: _lastReview,
      nextReviewDate: _lastReview.add(const Duration(days: 7)),
      cardState: CardState.review,
    ),
  });
  final species = await decksService.getSpeciesByDeckId(deckId);
  expect(species.map((s) => s.id), [
    _speciesA,
  ], reason: 'precondition: the deck holds species A before the update');
  return deckId;
}

final _lastReview = DateTime.fromMillisecondsSinceEpoch(1760000000000);

/// Confirms the update dialog the bootstrap's background check raises and
/// waits for the staged update's notice.
Future<void> _downloadUpdateUntilNoticeShows(
  WidgetTester tester,
  AppLocalizations loc,
) async {
  await tester.tap(find.text(loc.referenceDbUpdateConfirmUpdateNow));
  await waitForFinder(
    tester,
    find.byKey(const Key('reference_db_apply_notice')),
    description: 'the notice offering to apply the staged update',
  );
}

/// The context of the app currently built — after a restart, the new one's.
BuildContext _appContext(WidgetTester tester) =>
    tester.element(find.byType(FlashcardApp));

/// What the user data holds for [deckId]: species ID, stability and last
/// review of each card.
Future<List<Map<String, Object?>>> _cardsOf(String deckId) async {
  final userDb = await DatabaseHelper.userDb;
  return userDb.query(
    'flashcard_stats',
    columns: ['species_id', 'stability', 'last_review_date'],
    where: 'deck_id = ?',
    whereArgs: [deckId],
  );
}

/// Checks that the merged fixture is the reference database the app reads,
/// at version 2, with nothing left staged, and that the deck's card moved
/// from [_speciesA] to [_speciesB] with its learning state.
Future<void> _expectUpdateInstalledAndIdsRewritten(
  WidgetTester tester,
  String deckId,
) async {
  // Through the app's own connection, opened by the bootstrap after the
  // install; one still on the replaced file would not have it. It does not
  // tell whether the replaced file's -wal/-shm were removed: the app opens
  // the reference database read-only, so that write-ahead log is empty and
  // reading it over the new file changes nothing.
  final referenceDb = await DatabaseHelper.referenceDb;
  final marker = await referenceDb.query(
    'metadata',
    where: 'key = ?',
    whereArgs: [_markerKey],
  );
  expect(marker.map((row) => row['value']), [
    _markerValue,
  ], reason: 'the app reads the installed update, not the replaced file');

  expect(await ReferenceDatabaseProvisioner.currentVersion(), 2);
  final staged = StagedReferenceDb(
    await ReferenceDatabaseProvisioner.resolveLocalPath(),
  );
  expect(
    await File(staged.filePath).exists(),
    isFalse,
    reason: 'the staged file was moved into place',
  );
  expect(
    await File('${staged.filePath}.json').exists(),
    isFalse,
    reason: 'the staging metadata is cleared once installed',
  );

  final decksService = Provider.of<DecksService>(
    _appContext(tester),
    listen: false,
  );
  final species = await decksService.getSpeciesByDeckId(deckId);
  expect(species.map((s) => s.id), [_speciesB]);
  expect(await _cardsOf(deckId), [
    {
      'species_id': _speciesB,
      'stability': 7.5,
      'last_review_date': _lastReview.millisecondsSinceEpoch,
    },
  ], reason: 'the learning state moved with the card');
  final userDb = await DatabaseHelper.userDb;
  final onA = await userDb.query(
    'flashcard_stats',
    where: 'species_id = ?',
    whereArgs: [_speciesA],
  );
  expect(onA, isEmpty, reason: 'nothing refers to the merged-away ID');
}

/// Ends the running app's session and closes the databases — what leaving
/// the process does, and what a restart does before it bootstraps again.
/// Needs no tester, so tearDown can call it.
Future<void> _stopApp() async {
  final app = find.byType(FlashcardApp).evaluate();
  if (app.isNotEmpty) {
    await Provider.of<AppSession>(app.first, listen: false).stop();
  }
  await DatabaseHelper.close();
}

void main() {
  initializeIntegrationTest();

  group('reference db apply', () {
    setUp(() async {
      await resetTestState();
      await StagedReferenceDb(
        await ReferenceDatabaseProvisioner.resolveLocalPath(),
      ).clear();
    });

    // The merged fixture is left installed, and every later startApp seeds
    // the original over it in place — under whatever connection is still
    // open on it. So the restarted session is ended, the databases closed,
    // and the original fixture put back without the merged one's journal
    // files, for the next test to open fresh.
    tearDown(() async {
      await _stopApp();
      final path = await ReferenceDatabaseProvisioner.resolveLocalPath();
      await StagedReferenceDb(path).clear();
      await seedReferenceDb();
      await deleteJournalFiles(path);
    });

    testWidgets(
      'applying a staged update restarts once, installs it and moves the '
      'user data to the aliased IDs',
      (tester) async {
        final downloader = _MergedFixtureDownloader();
        await startApp(
          tester,
          notificationService: createMockNotificationService(),
          referenceDbDownloader: downloader,
        );
        final loc = AppLocalizations.of(
          tester.element(find.byType(MainScreenPage)),
        )!;
        await waitForFinder(
          tester,
          find.text(loc.referenceDbUpdateConfirmTitle),
          description: 'the reference-DB update dialog',
        );
        final deckId = await _seedUserDataOnSpeciesA(_appContext(tester));

        await _downloadUpdateUntilNoticeShows(tester, loc);
        expect(downloader.manifestFetches, 1);

        final endedSession = Provider.of<AppSession>(
          _appContext(tester),
          listen: false,
        );

        // Twice, with no frame in between: the first tap only schedules the
        // swap to the loading screen, so the notice is still there for the
        // second — a double tap. Both reach AppRestart; restartOnce is what
        // keeps the second from starting a restart of its own.
        final apply = find.byKey(
          const Key('reference_db_apply_notice_apply_button'),
        );
        await tester.tap(apply);
        await tester.tap(apply);

        // Until the app of a new session is up — the ended one's stays in
        // the tree until the next frame — or the restart ended on an error
        // screen, which the assertions below then report.
        await waitForCondition(tester, () {
          if (find
                  .byType(ReferenceDbDownloadErrorShell)
                  .evaluate()
                  .isNotEmpty ||
              find.byType(BootstrapErrorShell).evaluate().isNotEmpty) {
            return true;
          }
          final app = find.byType(MainScreenPage).evaluate();
          return app.isNotEmpty &&
              Provider.of<AppSession>(app.first, listen: false) != endedSession;
        }, description: 'the app of the restarted session');
        await safePumpAndSettle(tester);

        // A second restart would stop the ended session a second time and
        // bootstrap a second time, alongside the first. The app shows the
        // restart it was handed last, so where that one breaks is what the
        // user sees: in a debug build, disposing the enrichment queue a
        // second time throws, and the bootstrap error screen comes up. A
        // second restart that got through would be the third manifest check.
        final errorShells = find.byType(BootstrapErrorShell).evaluate();
        expect(
          errorShells,
          isEmpty,
          reason:
              'the restart ended on the bootstrap error screen: '
              '${errorShells.map((e) => (e.widget as BootstrapErrorShell).error)}',
        );
        expect(
          find.byType(ReferenceDbDownloadErrorShell),
          findsNothing,
          reason: 'the restart ended on the reference-DB error screen',
        );
        expect(
          downloader.manifestFetches,
          2,
          reason: 'one bootstrap at start and exactly one for the restart',
        );
        expect(find.byType(MainScreenPage), findsOneWidget);
        expect(
          find.byKey(const Key('reference_db_apply_notice')),
          findsNothing,
        );
        await _expectUpdateInstalledAndIdsRewritten(tester, deckId);
      },
      timeout: integrationTestTimeout,
    );

    testWidgets(
      '"Later" puts the notice aside, and the next app start installs the '
      'update anyway',
      (tester) async {
        await startApp(
          tester,
          notificationService: createMockNotificationService(),
          referenceDbDownloader: _MergedFixtureDownloader(),
        );
        final loc = AppLocalizations.of(
          tester.element(find.byType(MainScreenPage)),
        )!;
        await waitForFinder(
          tester,
          find.text(loc.referenceDbUpdateConfirmTitle),
          description: 'the reference-DB update dialog',
        );
        final deckId = await _seedUserDataOnSpeciesA(_appContext(tester));
        await _downloadUpdateUntilNoticeShows(tester, loc);

        await tester.tap(
          find.byKey(const Key('reference_db_apply_notice_later_button')),
        );
        await waitForAbsence(
          tester,
          find.byKey(const Key('reference_db_apply_notice')),
          description: 'the notice to be put aside',
        );
        final path = await ReferenceDatabaseProvisioner.resolveLocalPath();
        expect(
          await StagedReferenceDb(path).hasFile,
          isTrue,
          reason: '"Later" leaves the update staged',
        );

        // A new process, as far as the app can tell: the session ends, the
        // databases close, and the app starts from main() again. The old
        // tree is unmounted first — runApp() with the same root widget type
        // would keep the running BootstrapApp's state, and no bootstrap
        // would run at all.
        await _stopApp();
        await tester.pumpWidget(const SizedBox.shrink());
        await startApp(
          tester,
          notificationService: createMockNotificationService(),
          referenceDbDownloader: _MergedFixtureDownloader(),
        );
        await waitForFinder(tester, find.byType(MainScreenPage));

        expect(
          find.byKey(const Key('reference_db_apply_notice')),
          findsNothing,
        );
        await _expectUpdateInstalledAndIdsRewritten(tester, deckId);
      },
      timeout: integrationTestTimeout,
    );
  });
}
