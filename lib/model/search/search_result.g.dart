// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'search_result.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SearchResult _$SearchResultFromJson(Map<String, dynamic> json) => SearchResult(
  id: json['id'] as String,
  name: json['name'] as String,
  commonNames: (json['commonNames'] as Map<String, dynamic>).map(
    (k, e) => MapEntry($enumDecode(_$LanguageEnumMap, k), e as String?),
  ),
  type: $enumDecode(_$SearchEntityTypeEnumMap, json['type']),
);

Map<String, dynamic> _$SearchResultToJson(SearchResult instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'commonNames': instance.commonNames.map(
        (k, e) => MapEntry(_$LanguageEnumMap[k]!, e),
      ),
      'type': _$SearchEntityTypeEnumMap[instance.type]!,
    };

const _$LanguageEnumMap = {
  Language.de: 'de',
  Language.en: 'en',
  Language.fr: 'fr',
  Language.es: 'es',
};

const _$SearchEntityTypeEnumMap = {
  SearchEntityType.species: 'species',
  SearchEntityType.genus: 'genus',
  SearchEntityType.family: 'family',
  SearchEntityType.order: 'order',
  SearchEntityType.classType: 'classType',
};
