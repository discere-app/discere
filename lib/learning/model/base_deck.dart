import 'package:discere/shared/model/language.dart';
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
  @JsonKey(includeToJson: false, includeFromJson: false)
  Language language;
  @JsonKey(includeToJson: false)
  String? sourceId;
  @JsonKey(includeToJson: false)
  DateTime? updatedAt;

  BaseDeck(
    this.id,
    this.name,
    this.description, {
    this.coverImagePath,
    this.imageUrl,
    Language? language,
    this.sourceId,
    this.updatedAt,
  }) : language = language ?? Language.getSystemLanguage();

  factory BaseDeck.fromJson(Map<String, dynamic> json) =>
      _$BaseDeckFromJson(json);

  Map<String, dynamic> toJson() => _$BaseDeckToJson(this);
}
