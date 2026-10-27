import 'dart:convert';

import 'package:discere/learning/model/base_deck.dart';
import 'package:discere/learning/model/create_subdeck.dart';
import 'package:discere/learning/model/deck_format.dart';
import 'package:discere/learning/model/learning_mode.dart';
import 'package:discere/learning/model/name_type.dart';
import 'package:discere/learning/model/review_mode.dart';
import 'package:discere/shared/model/language.dart';
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
  /// it resolved or from species the user picked. Never read from JSON: an
  /// ID there would be unchecked, and a shared deck carries only scientific
  /// names ([toJson]).
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

  /// The learning mode a deck imported from this one starts with — written
  /// from the sharer's deck config, ignored by a catalog update, as after
  /// the import the setting is the user's. `null` where the deck sets none.
  @JsonKey(fromJson: _learningModeFromJson, toJson: _learningModeToJson)
  final LearningMode? learningMode;

  /// The name type a deck imported from this one starts with, like
  /// [learningMode].
  @JsonKey(fromJson: _nameTypeFromJson, toJson: _nameTypeToJson)
  final NameType? nameType;

  /// The review mode a deck imported from this one starts with, like
  /// [learningMode]. Not checked against the deck's names: a card short of
  /// answer options falls back to flipping during review on its own.
  @JsonKey(fromJson: _reviewModeFromJson, toJson: _reviewModeToJson)
  final ReviewMode? reviewMode;

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
    this.learningMode,
    this.nameType,
    this.reviewMode,
    super.imageUrl,
    super.sourceId,
    super.updatedAt,
  });

  /// [BaseDeck.copyWith], extended to this model's own fields, with the same
  /// rule: null leaves a field as it is.
  @override
  CreateDeck copyWith({
    String? id,
    String? name,
    String? description,
    String? coverImagePath,
    String? imageUrl,
    Language? language,
    String? sourceId,
    DateTime? updatedAt,
    Set<String>? speciesNames,
    Set<String>? speciesIds,
    List<CreateSubdeck>? subdecks,
    List<String>? supersedes,
    LearningMode? learningMode,
    NameType? nameType,
    ReviewMode? reviewMode,
  }) => CreateDeck(
    id: id ?? this.id,
    name: name ?? this.name,
    description: description ?? this.description,
    coverImagePath: coverImagePath ?? this.coverImagePath,
    imageUrl: imageUrl ?? this.imageUrl,
    language: language ?? this.language,
    sourceId: sourceId ?? this.sourceId,
    updatedAt: updatedAt ?? this.updatedAt,
    speciesNames: speciesNames ?? this.speciesNames,
    speciesIds: speciesIds ?? this.speciesIds,
    subdecks: subdecks ?? this.subdecks,
    supersedes: supersedes ?? this.supersedes,
    learningMode: learningMode ?? this.learningMode,
    nameType: nameType ?? this.nameType,
    reviewMode: reviewMode ?? this.reviewMode,
  );

  /// Reads a deck's JSON, holding its subdecks to what the format promises
  /// even where the JSON does not: a name in a subdeck but missing from
  /// `speciesNames` still belongs to the deck, a name in two subdecks stays
  /// in the first, and of two subdecks with one id the first is kept, its
  /// namesake's species belonging to none.
  factory CreateDeck.fromJson(Map<String, dynamic> json) =>
      _$CreateDeckFromJson(json)._withConsistentSubdecks();

  /// The deck's JSON, declaring the lowest format version that holds it.
  @override
  Map<String, dynamic> toJson() => DeckFormat.declare(_$CreateDeckToJson(this));

  /// Parse from a raw JSON string (e.g. pasted text).
  static CreateDeck fromJsonString(String jsonText) {
    final map = jsonDecode(jsonText) as Map<String, dynamic>;
    return CreateDeck.fromJson(map);
  }

  static LearningMode? _learningModeFromJson(Object? json) => _fromStorageValue(
    json,
    'learningMode',
    LearningMode.values,
    (mode) => mode.storageValue,
  );

  static NameType? _nameTypeFromJson(Object? json) => _fromStorageValue(
    json,
    'nameType',
    NameType.values,
    (type) => type.storageValue,
  );

  static ReviewMode? _reviewModeFromJson(Object? json) => _fromStorageValue(
    json,
    'reviewMode',
    ReviewMode.values,
    (mode) => mode.storageValue,
  );

  static String? _learningModeToJson(LearningMode? mode) => mode?.storageValue;

  static String? _nameTypeToJson(NameType? type) => type?.storageValue;

  static String? _reviewModeToJson(ReviewMode? mode) => mode?.storageValue;

  /// The one of [values] whose storage value [json] is, or `null`. A value
  /// only a newer app knows, or one of the wrong type, reads as a deck that
  /// sets none, rather than as no deck at all.
  static T? _fromStorageValue<T>(
    Object? json,
    String key,
    List<T> values,
    String Function(T value) storageValueOf,
  ) {
    if (json == null) return null;
    for (final value in values) {
      if (storageValueOf(value) == json) return value;
    }
    _log.warn('Ignoring the unknown $key "$json"');
    return null;
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
    return copyWith(
      speciesNames: {
        ...?speciesNames,
        for (final subdeck in subdecks) ...subdeck.speciesNames,
      },
      subdecks: consistent,
    );
  }
}
