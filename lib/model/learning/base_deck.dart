import 'package:json_annotation/json_annotation.dart';

@JsonSerializable()
class BaseDeck {
  @JsonKey(includeToJson: false)
  String? id;
  String name;
  String description;
  @JsonKey(includeToJson: false)
  String? coverImagePath;

  BaseDeck(this.id, this.name, this.description, {this.coverImagePath});
}

