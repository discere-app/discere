import 'package:discere/shared/model/language.dart';
import 'package:json_annotation/json_annotation.dart';

part 'base_deck.g.dart';

/// A deck as it is stored and passed around.
///
/// Immutable, like the models in `catalog/` and `enrichment/`: a deck
/// travels through providers and `ChangeNotifier`s, and a field assigned
/// somewhere along the way is a change nobody asked for and nobody saved.
/// [copyWith] is how a caller states the change it wants.
@JsonSerializable()
class BaseDeck {
  @JsonKey(includeToJson: false)
  final String? id;
  final String name;
  final String description;
  @JsonKey(includeToJson: false)
  final String? coverImagePath;
  final String? imageUrl;
  @JsonKey(includeToJson: false, includeFromJson: false)
  final Language language;
  @JsonKey(includeToJson: false)
  final String? sourceId;
  @JsonKey(includeToJson: false)
  final DateTime? updatedAt;

  /// Named throughout: id, name and description used to be three positional
  /// strings in a row, which a caller could swap without the compiler
  /// noticing.
  BaseDeck({
    this.id,
    required this.name,
    required this.description,
    this.coverImagePath,
    this.imageUrl,
    Language? language,
    this.sourceId,
    this.updatedAt,
  }) : language = language ?? Language.getSystemLanguage();

  factory BaseDeck.fromJson(Map<String, dynamic> json) =>
      _$BaseDeckFromJson(json);

  Map<String, dynamic> toJson() => _$BaseDeckToJson(this);

  /// A copy with the given fields replaced.
  ///
  /// Nullable fields cannot be cleared through this — passing null means
  /// "leave as is", which is what almost every caller wants. A deck that
  /// genuinely has to lose its cover image is built directly.
  BaseDeck copyWith({
    String? id,
    String? name,
    String? description,
    String? coverImagePath,
    String? imageUrl,
    Language? language,
    String? sourceId,
    DateTime? updatedAt,
  }) {
    return BaseDeck(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      coverImagePath: coverImagePath ?? this.coverImagePath,
      imageUrl: imageUrl ?? this.imageUrl,
      language: language ?? this.language,
      sourceId: sourceId ?? this.sourceId,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
