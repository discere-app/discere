import 'dart:async';

import 'package:discere/catalog/model/taxon_rank.dart';
import 'package:discere/external/inaturalist/inaturalist_service.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

/// Resolves iNaturalist search results and cached runtime taxonomy rows
/// against the bundled reference database, so the app can show a taxon the
/// user searched for even when it isn't already cached locally by name.
///
/// Two related but distinct flows live here because they share the
/// scientific-name → reference-id lookup machinery:
///  - [searchAndResolveINat]: live iNaturalist search, matched back to
///    reference-DB rows by scientific name (falling back to a synthetic
///    `inat:`-prefixed row when no reference match exists). The resolved
///    rows carry no `common_name_*` columns of their own — `SearchRepository`
///    runs them through the same `CommonNameRepository` merge as every other
///    branch, so a hit found only through this path still agrees with the
///    detail page. The live iNat-reported preferred English name is attached
///    separately (`inatPreferredCommonNameEnKey`) for `SearchRepository` to
///    fold into that merge, since it's the one piece of information this
///    resolver has that the reference/runtime DBs don't.
///  - [resolveRuntimeTaxonomyReferenceRows]: runtime-cached taxonomy search
///    rows (genus/family/order/class) that don't yet carry a resolved
///    `discere:` reference id get one resolved and attached.
class INatReferenceResolver {
  static final _log = Logger.forType(INatReferenceResolver);
  // Search logging includes the user's raw queries — keep it out of release
  // builds.
  static const bool _enableDebugLogging = kDebugMode;
  static const Duration _referenceSearchTimeout = Duration(milliseconds: 1200);
  static const int _referenceResultLimit = 20;

  /// Row key carrying the live iNat-reported preferred English common name
  /// for a resolved row, so `SearchRepository` can fold it into the merged
  /// English name list rather than trusting it as the sole answer.
  static const String inatPreferredCommonNameEnKey =
      '_inat_preferred_common_name_en';

  final Future<Database> Function() _referenceDatabase;
  final INaturalistService? _iNatService;

  const INatReferenceResolver({
    required Future<Database> Function() referenceDatabase,
    required INaturalistService? iNatService,
  }) : _referenceDatabase = referenceDatabase,
       _iNatService = iNatService;

  Future<List<Map<String, dynamic>>> searchAndResolveINat(String term) async {
    if (_iNatService == null) return const [];
    final iNatService = _iNatService;

    _logDebug('Search: querying iNat for "$term"');

    final inatResults = await iNatService.searchTaxa(term);

    _logDebug('Search: iNat API returned ${inatResults.length} taxa');

    if (inatResults.isEmpty) return const [];

    final speciesScientificNames = inatResults
        .where((result) => _isSpeciesRank(result['rank'] as String?))
        .map((result) => result['scientific_name'] as String)
        .where((name) => name.isNotEmpty)
        .toList();
    final taxonomyNamesByType = <String, Set<String>>{
      for (final rank in TaxonRank.values) rank.entityType: {},
    };

    for (final result in inatResults) {
      final scientificName = (result['scientific_name'] as String? ?? '')
          .trim();
      final entityType = _entityTypeForINatRank(result['rank'] as String?);
      if (scientificName.isEmpty || entityType == null) continue;
      taxonomyNamesByType[entityType]!.add(scientificName);
    }

    _logDebug(
      'Search: looking up ${speciesScientificNames.length} species and '
      '${taxonomyNamesByType.values.fold<int>(0, (sum, names) => sum + names.length)} '
      'higher-rank iNat taxa in reference DB',
    );

    final referenceMatchGroups = await Future.wait([
      _lookupSpeciesByScientificNames(speciesScientificNames),
      for (final rank in TaxonRank.values)
        _lookupTaxonomyByScientificNames(
          taxonomyNamesByType[rank.entityType]!.toList(),
          entityType: rank.entityType,
        ),
    ]);
    final referenceMatches = referenceMatchGroups
        .expand((matches) => matches)
        .toList();
    final directTaxonomyFallbackRows = _buildDirectINatTaxonomyFallbackRows(
      inatResults,
      referenceMatches,
    );

    _logDebug(
      'Search: ${referenceMatches.length}/${inatResults.length} iNat results matched reference DB',
    );

    // Build a map from scientific_name (lowercase) → preferred_common_name
    // from the iNat results so we can supplement local common names.
    final inatCommonNames = <String, String>{};
    for (final r in inatResults) {
      final name = (r['scientific_name'] as String).trim().toLowerCase();
      final preferred = r['preferred_common_name'] as String?;
      if (preferred != null && preferred.isNotEmpty) {
        inatCommonNames[name] = preferred;
      }
    }

    // Attach the live iNat preferred name alongside each matched row rather
    // than baking it into `common_name_en` here — these rows carry no
    // common-name columns of their own (`SearchRepository` resolves those
    // through the shared `CommonNameRepository` merge, same as every other
    // search branch), so folding the live name into that merge is
    // `SearchRepository`'s job.
    return referenceMatches.map((row) {
      final nameKey = (row['scientific_name'] as String).toLowerCase();
      final inatPreferred = inatCommonNames[nameKey];
      if (inatPreferred == null) return row;
      return {...row, inatPreferredCommonNameEnKey: inatPreferred};
    }).toList()..addAll(directTaxonomyFallbackRows);
  }

  bool _isSpeciesRank(String? rank) =>
      rank == 'species' || rank == 'subspecies';

  String? _entityTypeForINatRank(String? rank) =>
      TaxonRank.fromRankName(rank)?.entityType;

  Future<List<Map<String, dynamic>>> _lookupSpeciesByScientificNames(
    List<String> scientificNames,
  ) async {
    if (scientificNames.isEmpty) return const [];
    final db = await _referenceDatabase();
    final normalizedBinomials = scientificNames
        .map(_normalizeToBinomial)
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList();
    if (normalizedBinomials.isEmpty) return const [];

    try {
      final mergedById = <String, Map<String, dynamic>>{};

      for (final scientificName in normalizedBinomials) {
        final pair = _splitBinomial(scientificName);
        if (pair == null) {
          continue;
        }

        final rows = await db
            .rawQuery(
              '''
        SELECT s.id,
               g.name || ' ' || s.name AS scientific_name,
               'species' AS entity_type
        FROM species s
        JOIN genera g ON g.id = s.genus
        WHERE lower(trim(g.name)) = ?
          AND lower(trim(s.name)) = ?
          AND s.status = 'active'
        LIMIT 1
      ''',
              [pair.genus, pair.species],
            )
            .timeout(_referenceSearchTimeout, onTimeout: () => const []);

        if (rows.isNotEmpty) {
          _logDebug('Search: matched iNat "$scientificName"');
        }

        for (final row in rows) {
          mergedById[row['id'] as String] = row;
        }
      }

      return mergedById.values.toList();
    } on DatabaseException catch (e) {
      _logDebug('Search: species scientific-name lookup failed: $e');
      return const [];
    } on TimeoutException {
      return const [];
    }
  }

  String _normalizeToBinomial(String scientificName) {
    final parts = scientificName
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.length < 2) {
      return scientificName.trim().toLowerCase();
    }
    return '${parts[0]} ${parts[1]}';
  }

  ({String genus, String species})? _splitBinomial(String scientificName) {
    final parts = scientificName
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.length < 2) return null;
    return (genus: parts[0], species: parts[1]);
  }

  Future<List<Map<String, dynamic>>> _lookupTaxonomyByScientificNames(
    List<String> scientificNames, {
    required String entityType,
  }) async {
    if (scientificNames.isEmpty) return const [];

    final db = await _referenceDatabase();
    final normalizedNames = scientificNames
        .map((name) => name.trim().toLowerCase())
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList();
    if (normalizedNames.isEmpty) return const [];

    final tableName = _referenceTableForEntityType(entityType);
    const chunkSize = 100;

    try {
      final mergedById = <String, Map<String, dynamic>>{};

      for (var i = 0; i < normalizedNames.length; i += chunkSize) {
        final chunk = normalizedNames.skip(i).take(chunkSize).toList();
        final placeholders = List.filled(chunk.length, '?').join(', ');
        final rows = await db
            .rawQuery(
              '''
        SELECT t.id,
               t.name AS scientific_name,
               '$entityType' AS entity_type
        FROM $tableName t
        WHERE lower(trim(t.name)) IN ($placeholders)
        LIMIT $_referenceResultLimit
      ''',
              chunk,
            )
            .timeout(_referenceSearchTimeout, onTimeout: () => const []);

        for (final row in rows) {
          mergedById[row['id'] as String] = row;
        }
      }

      return mergedById.values.toList();
    } on DatabaseException {
      return const [];
    } on TimeoutException {
      return const [];
    }
  }

  String _referenceTableForEntityType(String entityType) {
    final rank = TaxonRank.fromEntityType(entityType);
    if (rank == null) {
      throw ArgumentError('Unsupported entity type: $entityType');
    }
    return rank.referenceTableName;
  }

  Future<List<Map<String, dynamic>>> resolveRuntimeTaxonomyReferenceRows(
    List<Map<String, dynamic>> rows,
  ) async {
    if (rows.isEmpty) return rows;

    final namesByType = <String, Set<String>>{};
    for (final row in rows) {
      final entityType = row['entity_type'] as String? ?? '';
      if (entityType == 'species' || !_isReferenceTaxonomyType(entityType)) {
        continue;
      }
      final existingId = row['entity_id'] as String? ?? row['id'] as String?;
      if (existingId != null && existingId.startsWith('discere:')) {
        continue;
      }
      final scientificName = (row['scientific_name'] as String? ?? '')
          .trim()
          .toLowerCase();
      if (scientificName.isEmpty) continue;
      namesByType.putIfAbsent(entityType, () => <String>{}).add(scientificName);
    }

    Map<String, Map<String, String>> referenceIdsByTypeAndName = const {};
    if (namesByType.isNotEmpty) {
      referenceIdsByTypeAndName = {};
      for (final entry in namesByType.entries) {
        referenceIdsByTypeAndName[entry.key] =
            await _lookupTaxonomyReferenceIds(
              entityType: entry.key,
              normalizedNames: entry.value.toList(growable: false),
            );
      }
    }

    return rows.map((row) {
      // Row already carries a resolved reference ID — align the id field.
      final entityId = row['entity_id'] as String?;
      if (entityId != null && entityId.startsWith('discere:')) {
        return row['id'] == entityId ? row : {...row, 'id': entityId};
      }

      final entityType = row['entity_type'] as String? ?? '';
      final scientificName = (row['scientific_name'] as String? ?? '')
          .trim()
          .toLowerCase();
      final referenceId =
          referenceIdsByTypeAndName[entityType]?[scientificName];
      if (referenceId == null) return row;

      return {...row, 'id': referenceId, 'entity_id': referenceId};
    }).toList();
  }

  bool _isReferenceTaxonomyType(String entityType) =>
      TaxonRank.fromEntityType(entityType) != null;

  Future<Map<String, String>> _lookupTaxonomyReferenceIds({
    required String entityType,
    required List<String> normalizedNames,
  }) async {
    if (normalizedNames.isEmpty) return const {};

    final db = await _referenceDatabase();
    final tableName = _referenceTableForEntityType(entityType);
    final placeholders = List.filled(normalizedNames.length, '?').join(', ');
    final rows = await db
        .rawQuery('''
      SELECT id, lower(trim(name)) AS normalized_name
      FROM $tableName
      WHERE lower(trim(name)) IN ($placeholders)
      ORDER BY id
      ''', normalizedNames)
        .timeout(_referenceSearchTimeout, onTimeout: () => const []);

    final counts = <String, int>{};
    final result = <String, String>{};
    for (final row in rows) {
      final name = row['normalized_name'] as String;
      counts[name] = (counts[name] ?? 0) + 1;
      result[name] = row['id'] as String;
    }
    // Remove homonyms — two distinct taxa with the same normalized name cannot
    // be reliably disambiguated here, so we leave them unresolved.
    counts.forEach((name, count) {
      if (count > 1) result.remove(name);
    });
    return result;
  }

  List<Map<String, dynamic>> _buildDirectINatTaxonomyFallbackRows(
    List<Map<String, dynamic>> inatResults,
    List<Map<String, dynamic>> referenceMatches,
  ) {
    final matchedKeys = referenceMatches
        .map(
          (row) =>
              '${row['entity_type']}:${(row['scientific_name'] as String).trim().toLowerCase()}',
        )
        .toSet();
    final fallbackRows = <Map<String, dynamic>>[];

    for (final result in inatResults) {
      final entityType = _entityTypeForINatRank(result['rank'] as String?);
      if (entityType == null) continue;

      final scientificName = (result['scientific_name'] as String? ?? '')
          .trim();
      if (scientificName.isEmpty) continue;

      final matchKey = '$entityType:${scientificName.toLowerCase()}';
      if (matchedKeys.contains(matchKey)) continue;

      fallbackRows.add({
        'id': 'inat:$matchKey',
        'scientific_name': scientificName,
        'common_name_en': result['preferred_common_name'] as String?,
        'common_name_de': null,
        'common_name_fr': null,
        'common_name_es': null,
        'entity_type': entityType,
      });
    }

    return fallbackRows;
  }

  void _logDebug(String message) {
    if (_enableDebugLogging) {
      _log.debug(message);
    }
  }
}
