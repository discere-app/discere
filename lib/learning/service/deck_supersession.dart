import 'package:discere/learning/model/base_deck.dart';
import 'package:discere/learning/model/create_deck.dart';

/// Which of the user's decks the online catalog supersedes: a local deck
/// imported from a catalog entry — by its `sourceId` — that another entry
/// lists in its `supersedes`. Such a deck hands its progress over to the
/// entries that supersede it, species by species (`DeckMergeService`).
///
/// Database-free, and the one place the question is answered, so the deck
/// list (through `DeckUpdateService`) and the online import tab cannot tell
/// the user two different things.
///
/// An entry without a `sourceId` supersedes nothing: once imported, it
/// could not be found again, and a merge that stopped half way could not be
/// finished.
class DeckSupersession {
  /// The catalog this was worked out from.
  final List<CreateDeck> catalog;

  final Map<String, BaseDeck> _localBySourceId;

  /// [localDecks] in the order the deck list shows them.
  DeckSupersession({
    required this.catalog,
    required Iterable<BaseDeck> localDecks,
  }) : _localBySourceId = {
         for (final deck in localDecks)
           if (deck.sourceId != null) deck.sourceId!: deck,
       };

  /// The local deck imported from [entry], if any.
  BaseDeck? localDeckOf(CreateDeck entry) =>
      entry.sourceId == null ? null : _localBySourceId[entry.sourceId];

  /// The local decks [entry] supersedes, in the order of the deck list.
  List<BaseDeck> decksSupersededBy(CreateDeck entry) {
    if (entry.sourceId == null) return const [];
    final superseded = entry.supersedes?.toSet() ?? const <String>{};
    return [
      for (final MapEntry(key: sourceId, value: deck)
          in _localBySourceId.entries)
        if (superseded.contains(sourceId) && sourceId != entry.sourceId) deck,
    ];
  }

  /// The catalog entries that supersede [deck].
  List<CreateDeck> entriesSuperseding(BaseDeck deck) => [
    for (final entry in catalog)
      if (decksSupersededBy(entry).any((d) => d.id == deck.id)) entry,
  ];

  /// The entry to merge [deck] into next: the first that supersedes it and
  /// is not imported yet — the others already took their share — or, once
  /// all are, the first of them, for a merge that stopped before [deck]
  /// was deleted.
  CreateDeck? replacementFor(BaseDeck deck) {
    final entries = entriesSuperseding(deck);
    if (entries.isEmpty) return null;
    return entries.firstWhere(
      (entry) => localDeckOf(entry) == null,
      orElse: () => entries.first,
    );
  }
}
