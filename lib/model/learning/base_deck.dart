import 'package:json_annotation/json_annotation.dart';
import 'package:discere/model/language.dart';

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
  @JsonKey(includeToJson: false, includeFromJson: false)
  Language language;

  BaseDeck(this.id, this.name, this.description,
      {this.coverImagePath,
      this.imageUrl,
      Language? language})
      : language = language ?? Language.getSystemLanguage();
}
