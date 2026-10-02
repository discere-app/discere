import 'dart:async';

import 'package:discere/catalog/common/species_list_item/species_list_item.dart';
import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'watchlist_page_harness.dart';

/// Covers WatchlistPage's two-pass load: the list renders from what is already
/// on disk and adopts the downloaded images whenever they arrive, instead of
/// showing a spinner until every missing image has been fetched. The downloaded
/// pass is strictly slower (network, and iNaturalist's rate limit serialises
/// it), so what matters here is that nothing on screen waits for it — and that
/// a result arriving after the watchlist changed is dropped rather than applied.

/// The image path the list item is currently rendering for [scientificName],
/// or null while it has none.
String? renderedImagePath(WidgetTester tester, String scientificName) {
  final item = tester
      .widgetList<SpeciesListItem>(find.byType(SpeciesListItem))
      .firstWhere((widget) => widget.item.scientificName.contains(scientificName));
  return item.item.localImagePath;
}

void main() {
  group('WatchlistPage two-pass load', () {
    testWidgets('renders the cached species before the download finishes', (
      tester,
    ) async {
      final download = Completer<List<SpeciesWithLocalImages>>();

      await pumpWatchlistPage(
        tester,
        watchlist: ['sp1', 'sp2'],
        resolveFromCache: (_) async => [
          watchlistItem('sp1', 'one'),
          watchlistItem('sp2', 'two'),
        ],
        resolveWithDownload: (_) => download.future,
      );
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('Genus one'), findsWidgets);
      expect(find.textContaining('Genus two'), findsWidgets);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(renderedImagePath(tester, 'Genus one'), isNull);

      download.complete(const []);
      await tester.pumpAndSettle();
    });

    testWidgets('adopts the downloaded images when they arrive', (tester) async {
      final download = Completer<List<SpeciesWithLocalImages>>();

      await pumpWatchlistPage(
        tester,
        watchlist: ['sp1'],
        resolveFromCache: (_) async => [watchlistItem('sp1', 'one')],
        resolveWithDownload: (_) => download.future,
      );
      await tester.pump();
      await tester.pump();
      expect(renderedImagePath(tester, 'Genus one'), isNull);

      download.complete([
        watchlistItem('sp1', 'one', localPath: '/local/sp1.jpg'),
      ]);
      await tester.pumpAndSettle();

      expect(renderedImagePath(tester, 'Genus one'), '/local/sp1.jpg');
    });

    testWidgets('keeps the cached list when the download fails', (tester) async {
      await pumpWatchlistPage(
        tester,
        watchlist: ['sp1'],
        resolveFromCache: (_) async => [watchlistItem('sp1', 'one')],
        resolveWithDownload: (_) async => throw Exception('offline'),
      );
      await tester.pumpAndSettle();

      // The cached view is a usable watchlist; a failed image fetch must not
      // replace it with an error message.
      expect(find.textContaining('Genus one'), findsWidgets);
      expect(find.textContaining('Fehler'), findsNothing);
    });

    testWidgets('reports an error only while there is nothing to show', (
      tester,
    ) async {
      await pumpWatchlistPage(
        tester,
        watchlist: ['sp1'],
        resolveFromCache: (_) async => throw Exception('db gone'),
        resolveWithDownload: (_) async => const [],
      );
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining('Genus one'), findsNothing);
      // errorWithDetail/describeError, not the raw exception text.
      expect(find.textContaining('db gone'), findsNothing);
    });

    testWidgets('discards a download result that lands before the reload', (
      tester,
    ) async {
      final firstDownload = Completer<List<SpeciesWithLocalImages>>();
      final pendingReload = Completer<List<SpeciesWithLocalImages>>();
      var cacheCalls = 0;

      await pumpWatchlistPage(
        tester,
        watchlist: ['sp1', 'sp2'],
        resolveFromCache: (ids) {
          cacheCalls++;
          if (cacheCalls == 1) {
            return Future.value([
              for (final id in ids)
                watchlistItem(id, id == 'sp1' ? 'one' : 'two'),
            ]);
          }
          // The reload for the shortened list is held back, so it cannot repair
          // a stale result that was wrongly applied.
          return pendingReload.future;
        },
        resolveWithDownload: (_) => firstDownload.future,
      );
      await tester.pump();
      await tester.pump();

      // Remove via the delete button, so the removal is not wrapped in a
      // Dismissible animation: _onRemove has run and the rebuild that starts
      // the reload is still pending.
      await tester.tap(find.byIcon(Icons.delete_outline).first);

      // The download started for {sp1, sp2} answers in exactly that gap. Only
      // invalidating the in-flight load inside _onRemove keeps sp1 off screen;
      // waiting for the rebuild to notice the changed id set is one frame too
      // late.
      firstDownload.complete([
        watchlistItem('sp1', 'one'),
        watchlistItem('sp2', 'two'),
      ]);
      await tester.idle();
      await tester.pump();

      expect(find.textContaining('Genus one'), findsNothing);
      expect(find.textContaining('Genus two'), findsWidgets);

      pendingReload.complete([watchlistItem('sp2', 'two')]);
      await tester.pumpAndSettle();
    });

    testWidgets('discards a download result for a list no longer shown', (
      tester,
    ) async {
      final firstDownload = Completer<List<SpeciesWithLocalImages>>();
      var downloadCalls = 0;

      final watchlistService = await pumpWatchlistPage(
        tester,
        watchlist: ['sp1', 'sp2'],
        resolveFromCache: (ids) async => [
          for (final id in ids)
            watchlistItem(id, id == 'sp1' ? 'one' : 'two'),
        ],
        resolveWithDownload: (ids) {
          downloadCalls++;
          if (downloadCalls == 1) return firstDownload.future;
          return Future.value([
            for (final id in ids)
              watchlistItem(
                id,
                id == 'sp1' ? 'one' : 'two',
                localPath: '/local/$id.jpg',
              ),
          ]);
        },
      );
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('Genus one'), findsWidgets);

      await tester.fling(
        find.textContaining('Genus one').first,
        const Offset(-500, 0),
        1000,
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Genus one'), findsNothing);
      expect(watchlistService.getSpecies(), {'sp2'});

      // The first download was started for {sp1, sp2} and only answers now.
      // Applying it would undo the optimistic removal and re-add a Dismissible
      // that has already been dismissed.
      firstDownload.complete([
        watchlistItem('sp1', 'one', localPath: '/local/sp1.jpg'),
        watchlistItem('sp2', 'two', localPath: '/local/sp2.jpg'),
      ]);
      await tester.pumpAndSettle();

      expect(find.textContaining('Genus one'), findsNothing);
      expect(find.textContaining('Genus two'), findsWidgets);
    });
  });
}
