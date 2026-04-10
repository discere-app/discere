import 'package:json_annotation/json_annotation.dart';

import 'package:discere/shared/model/language.dart';

part 'search_result.g.dart';

enum SearchEntityType { species, genus, family, order, classType }

@JsonSerializable()
class SearchResult {
  final String id;
  final String name;
  final Map<Language, String?> commonNames;
  final SearchEntityType type;

  SearchResult({
    required this.id,
    required this.name,
    required this.commonNames,
    required this.type,
  });

  factory SearchResult.fromJson(Map<String, dynamic> json) =>
      _$SearchResultFromJson(json);

  Map<String, dynamic> toJson() => _$SearchResultToJson(this);
}
