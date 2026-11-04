import 'dart:async';

import 'package:discere/catalog/common/species_with_images_loader.dart';
import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:flutter_test/flutter_test.dart';

import '../watchlist/watchlist_tab_harness.dart';

List<SpeciesWithLocalImages> _items(Set<String> ids) => [
  for (final id in ids) watchlistItem(id, 'species$id'),
];

void main() {
  late Completer<List<SpeciesWithLocalImages>> cache;
  late Completer<List<SpeciesWithLocalImages>> download;
  late int changes;
  late SpeciesWithImagesLoader loader;

  setUp(() {
    cache = Completer();
    download = Completer();
    changes = 0;
    loader = SpeciesWithImagesLoader(
      resolveFromCache: (_) => cache.future,
      resolveWithDownload: (_) => download.future,
      onChanged: () => changes++,
      log: Logger.forType(SpeciesWithImagesLoader),
    );
  });

  List<String>? shownIds() =>
      loader.species?.map((entry) => entry.species.id).toList();

  test('shows the cached species first, then the downloaded ones', () async {
    final load = loader.load({'a', 'b'});
    expect(loader.species, isNull);

    cache.complete(_items({'a', 'b'}));
    await pumpEventQueue();
    expect(shownIds(), ['a', 'b']);

    final withImages = _items({'a', 'b'});
    download.complete(withImages);
    await load;
    expect(loader.species, same(withImages));
    expect(changes, 2);
  });

  test('a result that arrives after a removal does not bring the species '
      'back', () async {
    final load = loader.load({'a', 'b'});
    cache.complete(_items({'a', 'b'}));
    await pumpEventQueue();

    loader.removeOptimistically('a');
    expect(shownIds(), ['b']);

    // The download was started for the set that still held 'a'.
    download.complete(_items({'a', 'b'}));
    await load;
    expect(shownIds(), ['b']);
  });

  test('a failed cache pass is the load error; a failed download keeps the '
      'cached species', () async {
    final failing = loader.load({'a'});
    cache.completeError(StateError('db'));
    await failing;
    expect(loader.loadError, isA<StateError>());
    expect(loader.species, isNull);

    cache = Completer();
    final retry = loader.load({'a'});
    cache.complete(_items({'a'}));
    await pumpEventQueue();
    download.completeError(StateError('network'));
    await retry;
    expect(loader.loadError, isNull);
    expect(shownIds(), ['a']);
  });

  test('nothing is applied after dispose', () async {
    final load = loader.load({'a'});
    loader.dispose();
    cache.complete(_items({'a'}));
    await load;
    expect(loader.species, isNull);
    expect(changes, 0);
  });
}
