import 'package:json_annotation/json_annotation.dart';

part 'base_deck.g.dart';

@JsonSerializable()
class BaseDeck {
  @JsonKey(includeToJson: false)
  String? id;
  String name;
  String description;
  @JsonKey(includeToJson: false)
  String? coverImagePath;
  String? imageUrl;

  BaseDeck(this.id, this.name, this.description, {this.coverImagePath, this.imageUrl});
}
