/// A subdeck of a stored deck, as the edit page shows it.
class Subdeck {
  final String deckId;

  /// The id the deck's JSON gave it (`CreateSubdeck.id`).
  final String id;
  final String name;
  final int sortOrder;

  /// Whether its species are cards. A switched-off subdeck keeps its
  /// species and their progress; they are only left out when read.
  final bool isActive;

  const Subdeck({
    required this.deckId,
    required this.id,
    required this.name,
    required this.sortOrder,
    required this.isActive,
  });

  /// A `deck_subdecks` row.
  factory Subdeck.fromMap(Map<String, dynamic> map) => Subdeck(
    deckId: map['deck_id'] as String,
    id: map['subdeck_id'] as String,
    name: map['name'] as String,
    sortOrder: map['sort_order'] as int,
    isActive: map['is_active'] == 1,
  );
}
