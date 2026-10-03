import 'dart:async';

import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:flutter_test/flutter_test.dart';

import 'watchlist_tab_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WatchlistTab dismiss', () {
    testWidgets(
      'dismissed species stays removed while a slow reload is still resolving',
      (tester) async {
        final reloadCompleter = Completer<List<SpeciesWithLocalImages>>();
        int callCount = 0;

        Future<List<SpeciesWithLocalImages>> resolveFromCache(
          Set<String> ids,
        ) async {
          callCount++;
          if (callCount == 1) {
            return [watchlistItem('sp1', 'one'), watchlistItem('sp2', 'two')];
          }
          // Second call happens after dismissing sp1 — kept pending on
          // purpose to exercise the reload-still-in-flight window.
          return reloadCompleter.future;
        }

        await pumpWatchlistTab(
          tester,
          watchlist: ['sp1', 'sp2'],
          resolveFromCache: resolveFromCache,
          // Same species as the cached pass, only with their images — what the
          // download pass is for. Returning anything else here would be the
          // test lying about the two passes agreeing on the list.
          resolveWithDownload: (ids) async => [
            for (final id in ids)
              watchlistItem(
                id,
                id == 'sp1' ? 'one' : 'two',
                localPath: '/local/$id.jpg',
              ),
          ],
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('Genus one'), findsWidgets);
        expect(find.textContaining('Genus two'), findsWidgets);

        // Swipe to dismiss "Genus one". This triggers a reload (via
        // WatchlistService.notifyListeners() -> hasChanged) that stays pending
        // on `reloadCompleter` for a few pumps below — regression coverage for
        // a bug where a stale load result clobbered the optimistic removal and
        // re-added the dismissed item, crashing with "A dismissed Dismissible
        // widget is still part of the tree."
        await tester.fling(
          find.textContaining('Genus one').first,
          const Offset(-500, 0),
          1000,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.textContaining('Genus one'), findsNothing);

        reloadCompleter.complete([watchlistItem('sp2', 'two')]);
        await tester.pumpAndSettle();

        expect(find.textContaining('Genus one'), findsNothing);
        expect(find.textContaining('Genus two'), findsWidgets);
      },
    );
  });
}
