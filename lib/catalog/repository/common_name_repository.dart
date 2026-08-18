import 'package:discere/catalog/model/locale_place_mapping.dart';
import 'package:discere/catalog/repository/locale_aware_common_name_sql.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:sqflite/sqflite.dart';

/// Shared reference-DB + runtime (`runtime_common_names`) common-name
/// lookup and merge logic.
///
/// Both the species detail page (`SpeciesRepository`) and search
/// (`SearchRepository`) need to resolve the same "primary common name" for
/// a given entity/locale — this class is the single place that decides the
/// per-language ordering and the reference-vs-runtime priority rule, so the
/// two surfaces can never disagree.
class CommonNameRepository {
  static final _log = Logger.forType(CommonNameRepository);
  static const bool _enableDebugLogging = true;
  static const int _chunkSize = 900;

  final LocalePlaceMapping? _localeMapping;

  const CommonNameRepository({LocalePlaceMapping? localeMapping})
    : _localeMapping = localeMapping;

  /// Bulk-loads the full, locale-ordered common-name list per language from
  /// the reference DB's `common_names` table for [entityIds] (species,
  /// genus, family, order, or class reference ids — they share one id
  /// space, so a single mixed-type `IN` query is valid). Ordered by country
  /// preference, `is_preferred DESC`, `rank ASC`; capped at 20 names per
  /// (entity, language).
  Future<Map<String, Map<Language, List<String>>>> loadReferenceCommonNames(
    Database db,
    Set<String> entityIds,
  ) async {
    if (entityIds.isEmpty) return {};

    final result = <String, Map<Language, List<String>>>{};
    final idList = entityIds.toList();

    final countryPref = sqlSafeCountryCode(_localeMapping?.countryCodeNumeric);
    final countryOrder = countryPref != null
        ? "(cn.country = '$countryPref') DESC, (cn.country IS NULL) DESC"
        : '(cn.country IS NULL) DESC';

    for (var i = 0; i < idList.length; i += _chunkSize) {
      final chunk = idList.skip(i).take(_chunkSize).toList();
      final placeholders = List.filled(chunk.length, '?').join(', ');
      final stopwatch = Stopwatch()..start();
      final rows = await db.rawQuery('''
        SELECT cn.entity_id, cn.language, cn.name
        FROM common_names cn
        WHERE cn.entity_id IN ($placeholders)
        ORDER BY cn.entity_id, cn.language,
                 $countryOrder,
                 cn.is_preferred DESC, cn.rank ASC
      ''', chunk);
      stopwatch.stop();
      _logDebug(
        'Common names: reference lookup '
        '(chunk=${chunk.length}, rows=${rows.length}, '
        '${stopwatch.elapsedMilliseconds}ms)',
      );

      for (final row in rows) {
        final entityId = row['entity_id'] as String;
        final name = (row['name'] as String?)?.trim() ?? '';
        if (name.isEmpty) continue;
        final language = _languageFromCode(row['language'] as String);
        if (language == null) continue;

        final names = result
            .putIfAbsent(entityId, () => {})
            .putIfAbsent(language, () => []);
        if (names.length < 20) {
          names.add(name);
        }
      }
    }

    _deduplicateCommonNameMap(result);
    return result;
  }

  /// Bulk-loads the full, locale/place-ordered common-name list per language
  /// from the user DB's `runtime_common_names` table for [entityKeys]
  /// (`species:<id>` or `genus:<lowercased name>` etc — mixed types are
  /// fine in one query).
  Future<Map<String, Map<Language, List<String>>>> loadRuntimeCommonNames(
    Database userDb,
    Set<String> entityKeys,
  ) async {
    if (entityKeys.isEmpty) return {};

    final namesByEntity = <String, Map<Language, List<String>>>{};
    final keyList = entityKeys.toList();

    for (var i = 0; i < keyList.length; i += _chunkSize) {
      final chunk = keyList.skip(i).take(_chunkSize).toList();
      final placeholders = List.filled(chunk.length, '?').join(', ');
      final stopwatch = Stopwatch()..start();
      final rows = await userDb.rawQuery('''
        SELECT entity_key, language_code, name
        FROM runtime_common_names
        WHERE entity_key IN ($placeholders)
        ORDER BY entity_key, language_code,
                 ${_runtimePlaceOrderBy()},
                 COALESCE(position, 999999),
                 COALESCE(place_position, 999999)
        ''', chunk);
      stopwatch.stop();
      _logDebug(
        'Common names: runtime lookup '
        '(chunk=${chunk.length}, rows=${rows.length}, '
        '${stopwatch.elapsedMilliseconds}ms)',
      );

      for (final row in rows) {
        final entityKey = row['entity_key'] as String;
        final name = (row['name'] as String?)?.trim() ?? '';
        if (name.isEmpty) continue;
        final language = _languageFromCode(row['language_code'] as String);
        if (language == null) continue;

        namesByEntity
            .putIfAbsent(entityKey, () => {})
            .putIfAbsent(language, () => [])
            .add(name);
      }
    }

    _deduplicateCommonNameMap(namesByEntity);
    return namesByEntity;
  }

  /// The single priority rule shared by every screen: runtime/imported
  /// names win and come first, reference names fill in after, deduped
  /// case/whitespace-insensitively.
  Map<Language, List<String>> merge(
    Map<Language, List<String>> referenceNames,
    Map<Language, List<String>> runtimeNames,
  ) {
    final merged = <Language, List<String>>{};

    for (final language in Language.values) {
      final imported = runtimeNames[language] ?? const [];
      final reference = referenceNames[language] ?? const [];
      merged[language] = _mergeNameLists(imported, reference);
    }

    return merged;
  }

  List<String> _mergeNameLists(List<String> primary, List<String> secondary) {
    if (secondary.isEmpty) return primary;
    if (primary.isEmpty) return secondary;

    final result = <String>[];
    final seen = <String>{};

    for (final name in [...primary, ...secondary]) {
      final normalized = name
          .trim()
          .replaceAll(RegExp(r'\s+'), ' ')
          .toLowerCase();
      if (normalized.isEmpty || seen.contains(normalized)) continue;
      seen.add(normalized);
      result.add(name);
    }

    return result;
  }

  Language? _languageFromCode(String code) {
    for (final language in Language.values) {
      if (language.name == code) return language;
    }
    return null;
  }

  void _deduplicateCommonNameMap(
    Map<String, Map<Language, List<String>>> nameMap,
  ) {
    for (final entityNames in nameMap.values) {
      for (final language in entityNames.keys) {
        final names = entityNames[language]!;
        if (names.length <= 1) continue;
        final seen = <String>{};
        final deduped = <String>[];
        for (final name in names) {
          final normalized = name
              .trim()
              .replaceAll(RegExp(r'\s+'), ' ')
              .toLowerCase();
          if (normalized.isEmpty || seen.contains(normalized)) continue;
          seen.add(normalized);
          deduped.add(name);
        }
        entityNames[language] = deduped;
      }
    }
  }

  /// ORDER BY fragment for `runtime_common_names` queries.
  ///
  /// When a locale mapping is available, the user's regional place is sorted
  /// first, followed by global names (`place_id IS NULL`).
  String _runtimePlaceOrderBy() {
    final placeId = _localeMapping?.inatPlaceId;
    if (placeId == null) return '(place_id IS NULL) DESC';
    return '(place_id = $placeId) DESC, (place_id IS NULL) DESC';
  }

  void _logDebug(String message) {
    if (_enableDebugLogging) {
      _log.debug(message);
    }
  }
}
