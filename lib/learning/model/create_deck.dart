import 'dart:convert';

import 'package:discere/learning/model/base_deck.dart';
import 'package:discere/learning/model/create_subdeck.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:json_annotation/json_annotation.dart';

part 'create_deck.g.dart';

@JsonSerializable(includeIfNull: false, explicitToJson: true)
class CreateDeck extends BaseDeck {
  static final _log = Logger.forType(CreateDeck);

  /// Every species of the deck, those in [subdecks] included — an app that
  /// knows nothing of subdecks imports the whole deck from this alone.
  final Set<String>? speciesNames;

  /// IDs of the installed reference database, set by the app — from names
  /// it resolved ([withSpeciesIds]) or from species the user picked. Never
  /// read from JSON: an ID there would be unchecked, and a shared deck
  /// carries only scientific names ([toJson]).
  @JsonKey(includeFromJson: false, includeToJson: false)
  final Set<String>? speciesIds;

  /// The deck's parts, such as difficulty levels, each of which the user can
  /// switch off; `null` for a deck without. A name belongs to at most one of
  /// them, and a species in none is always a card.
  final List<CreateSubdeck>? subdecks;

  /// The `sourceId`s of the catalog entries this one replaces. Local decks
  /// imported from those hand their progress over to this one, species by
  /// species (`DeckMergeService`). Read from the catalog and never written:
  /// like [sourceId], it refers to the catalog, not to a shared deck.
  @JsonKey(includeToJson: false)
  final List<String>? supersedes;

  CreateDeck({
    super.id,
    required super.name,
    required super.description,
    super.coverImagePath,
    super.language,
    this.speciesNames,
    this.speciesIds,
    this.subdecks,
    this.supersedes,
    super.imageUrl,
    super.sourceId,
    super.updatedAt,
  });

  /// A copy with the resolved species ids filled in — the one change this
  /// model sees, once a name lookup has turned names into ids.
  CreateDeck withSpeciesIds(Set<String> speciesIds) => CreateDeck(
    id: id,
    name: name,
    description: description,
    coverImagePath: coverImagePath,
    language: language,
    speciesNames: speciesNames,
    speciesIds: speciesIds,
    subdecks: subdecks,
    supersedes: supersedes,
    imageUrl: imageUrl,
    sourceId: sourceId,
    updatedAt: updatedAt,
  );

  /// Reads a deck's JSON, holding its subdecks to what the format promises
  /// even where the JSON does not: a name in a subdeck but missing from
  /// `speciesNames` still belongs to the deck, a name in two subdecks stays
  /// in the first, and of two subdecks with one id the first is kept, its
  /// namesake's species belonging to none.
  factory CreateDeck.fromJson(Map<String, dynamic> json) =>
      _$CreateDeckFromJson(json)._withConsistentSubdecks();

  @override
  Map<String, dynamic> toJson() => _$CreateDeckToJson(this);

  /// Parse from a raw JSON string (e.g. pasted text).
  static CreateDeck fromJsonString(String jsonText) {
    final map = jsonDecode(jsonText) as Map<String, dynamic>;
    return CreateDeck.fromJson(map);
  }

  CreateDeck _withConsistentSubdecks() {
    final subdecks = this.subdecks;
    if (subdecks == null) return this;
    final subdeckIds = <String>{};
    final assignedNames = <String>{};
    final dropped = <String>[];
    final consistent = <CreateSubdeck>[];
    for (final subdeck in subdecks) {
      if (!subdeckIds.add(subdeck.id)) {
        dropped.add('subdeck ${subdeck.id}');
        continue;
      }
      final names = <String>{};
      for (final name in subdeck.speciesNames) {
        if (assignedNames.add(name)) {
          names.add(name);
        } else {
          dropped.add('$name in ${subdeck.id}');
        }
      }
      consistent.add(
        CreateSubdeck(id: subdeck.id, name: subdeck.name, speciesNames: names),
      );
    }
    if (dropped.isNotEmpty) {
      _log.warn(
        'Deck "$name": kept only the first of each duplicate: '
        '${dropped.join(', ')}',
      );
    }
    return CreateDeck(
      id: id,
      name: name,
      description: description,
      coverImagePath: coverImagePath,
      language: language,
      speciesNames: {
        ...?speciesNames,
        for (final subdeck in subdecks) ...subdeck.speciesNames,
      },
      speciesIds: speciesIds,
      subdecks: consistent,
      supersedes: supersedes,
      imageUrl: imageUrl,
      sourceId: sourceId,
      updatedAt: updatedAt,
    );
  }
}
