import 'package:discere/shared/model/language.dart';
import 'package:json_annotation/json_annotation.dart';

part 'search_result.g.dart';

enum SearchEntityType { species, genus, family, order, classType }

@JsonSerializable()
class SearchResult {
  final String id;
  final String name;
  final Map<Language, List<String>> commonNames;
  final SearchEntityType type;

  /// Whether this is a source's rank placeholder ("Not assigned") rather
  /// than a taxon — see `Classification.placeholderRanks`.
  final bool isPlaceholder;

  /// The synonym this species was found through; `null` when it was found
  /// directly.
  final String? matchedSynonym;

  SearchResult({
    required this.id,
    required this.name,
    required this.commonNames,
    required this.type,
    this.isPlaceholder = false,
    this.matchedSynonym,
  });

  factory SearchResult.fromJson(Map<String, dynamic> json) =>
      _$SearchResultFromJson(json);

  Map<String, dynamic> toJson() => _$SearchResultToJson(this);
}
