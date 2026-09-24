import 'dart:convert';

import 'package:discere/learning/model/base_deck.dart';
import 'package:discere/shared/model/json_encodable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'create_deck.g.dart';

@JsonSerializable(includeIfNull: false)
class CreateDeck extends BaseDeck implements JsonEncodable {
  final Set<String>? speciesNames;

  @JsonKey(includeToJson: false)
  final Set<String>? speciesIds;

  CreateDeck({
    super.id,
    required super.name,
    required super.description,
    super.coverImagePath,
    super.language,
    this.speciesNames,
    this.speciesIds,
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
    imageUrl: imageUrl,
    sourceId: sourceId,
    updatedAt: updatedAt,
  );

  factory CreateDeck.fromJson(Map<String, dynamic> json) =>
      _$CreateDeckFromJson(json);

  @override
  Map<String, dynamic> toJson() => _$CreateDeckToJson(this);

  /// Parse from a raw JSON string (e.g. pasted text).
  static CreateDeck fromJsonString(String jsonText) {
    final map = jsonDecode(jsonText) as Map<String, dynamic>;
    return CreateDeck.fromJson(map);
  }
}
