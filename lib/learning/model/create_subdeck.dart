import 'package:json_annotation/json_annotation.dart';

part 'create_subdeck.g.dart';

/// A subdeck as a deck's JSON names it — in the catalog, in a shared file
/// or QR code: a part of the deck, such as a difficulty level, that the user
/// can switch off.
@JsonSerializable()
class CreateSubdeck {
  /// Stable across versions of the deck: an update finds the subdeck again
  /// by it, and keeps whether the user switched it off.
  final String id;
  final String name;
  final Set<String> speciesNames;

  const CreateSubdeck({
    required this.id,
    required this.name,
    required this.speciesNames,
  });

  factory CreateSubdeck.fromJson(Map<String, dynamic> json) =>
      _$CreateSubdeckFromJson(json);

  Map<String, dynamic> toJson() => _$CreateSubdeckToJson(this);
}
