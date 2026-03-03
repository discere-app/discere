import 'dart:convert';

import 'package:json_annotation/json_annotation.dart';

import '../learning/base_deck.dart';

part 'create_deck.g.dart';

@JsonSerializable()
class CreateDeck extends BaseDeck {
  final Set<String>? speciesNames;
  Set<String>? speciesIds;

  CreateDeck({
    String? id,
    required String name,
    required String description,
    this.speciesNames,
    this.speciesIds,
  }) : super(id, name, description);

  factory CreateDeck.fromJson(Map<String, dynamic> json) =>
      _$CreateDeckFromJson(json);

  Map<String, dynamic> toJson() => _$CreateDeckToJson(this);

  /// Parse from a raw JSON string (e.g. pasted text).
  static CreateDeck fromJsonString(String jsonText) {
    final map = jsonDecode(jsonText) as Map<String, dynamic>;
    return CreateDeck.fromJson(map);
  }
}
