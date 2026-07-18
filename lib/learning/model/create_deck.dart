import 'dart:convert';

import 'package:discere/learning/model/base_deck.dart';
import 'package:discere/shared/model/json_encodable.dart';
import 'package:discere/shared/model/language.dart';
import 'package:json_annotation/json_annotation.dart';

part 'create_deck.g.dart';

@JsonSerializable(includeIfNull: false)
class CreateDeck extends BaseDeck implements JsonEncodable {
  final Set<String>? speciesNames;

  @JsonKey(includeToJson: false)
  Set<String>? speciesIds;

  CreateDeck({
    String? id,
    required String name,
    required String description,
    Language? language,
    this.speciesNames,
    this.speciesIds,
    String? imageUrl,
    String? sourceId,
    DateTime? updatedAt,
  }) : super(
         id,
         name,
         description,
         imageUrl: imageUrl,
         language: language,
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
