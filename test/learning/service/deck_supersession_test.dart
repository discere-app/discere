import 'package:discere/learning/model/base_deck.dart';
import 'package:discere/learning/model/create_deck.dart';
import 'package:discere/learning/service/deck_supersession.dart';
import 'package:flutter_test/flutter_test.dart';

BaseDeck _local(String sourceId) => BaseDeck(
  id: 'local-$sourceId',
  name: sourceId,
  description: '',
  sourceId: sourceId,
);

CreateDeck _entry(String? sourceId, {List<String>? supersedes}) => CreateDeck(
  name: 'entry $sourceId',
  description: '',
  sourceId: sourceId,
  supersedes: supersedes,
);

/// Catalog entries are decks too.
List<String?> _names(Iterable<BaseDeck> decks) => [
  for (final deck in decks) deck.sourceId,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('an entry supersedes the local decks it lists, in deck-list order, '
      'never itself and never one that is not imported', () {
    final entry = _entry('all', supersedes: ['l2', 'l1', 'all', 'missing']);
    final supersession = DeckSupersession(
      catalog: [entry],
      localDecks: [_local('l1'), _local('other'), _local('l2'), _local('all')],
    );

    expect(_names(supersession.decksSupersededBy(entry)), ['l1', 'l2']);
  });

  test('an entry without sourceId supersedes nothing', () {
    final entry = _entry(null, supersedes: ['l1']);
    final supersession = DeckSupersession(
      catalog: [entry],
      localDecks: [_local('l1')],
    );

    expect(supersession.decksSupersededBy(entry), isEmpty);
    expect(supersession.replacementFor(_local('l1')), isNull);
  });

  test('a deck split into two entries is replaced by the one not imported '
      'yet, and by the first once both are', () {
    final fish = _entry('fish', supersedes: ['old']);
    final rays = _entry('rays', supersedes: ['old']);
    final old = _local('old');

    final neither = DeckSupersession(catalog: [fish, rays], localDecks: [old]);
    expect(_names(neither.entriesSuperseding(old)), ['fish', 'rays']);
    expect(neither.replacementFor(old)?.sourceId, 'fish');

    final fishImported = DeckSupersession(
      catalog: [fish, rays],
      localDecks: [old, _local('fish')],
    );
    expect(fishImported.replacementFor(old)?.sourceId, 'rays');

    final both = DeckSupersession(
      catalog: [fish, rays],
      localDecks: [old, _local('fish'), _local('rays')],
    );
    expect(both.replacementFor(old)?.sourceId, 'fish');
  });

  test('a deck no entry lists is not superseded', () {
    final supersession = DeckSupersession(
      catalog: [
        _entry('a', supersedes: ['b']),
      ],
      localDecks: [_local('c')],
    );

    expect(supersession.replacementFor(_local('c')), isNull);
  });
}
