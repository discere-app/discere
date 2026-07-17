import 'dart:async';

import 'package:discere/catalog/model/locale_place_mapping.dart';
import 'package:discere/catalog/model/search_result.dart';
import 'package:discere/catalog/repository/locale_aware_common_name_sql.dart';
import 'package:discere/catalog/repository/runtime_common_name_search_repository.dart';
import 'package:discere/catalog/search/search_worker.dart';
import 'package:discere/external/inaturalist/inaturalist_service.dart';
import 'package:discere/shared/persistence/database_helper.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

class SearchRepository {
  static final _log = Logger.forType(SearchRepository);
  // Search logging includes the user's raw queries — keep it out of release
  // builds.
  static const bool _enableSearchDebugLogging = kDebugMode;
  static const Duration _referenceSearchTimeout = Duration(milliseconds: 1200);
  static const int _referenceResultLimit = 20;
  static const int _runtimeCommonNameResultLimit = 25;
  static const int _fallbackThreshold = 5;

  final Database? _injectedReferenceDb;
  final Database? _injectedUserDb;
  final INaturalistService? _iNatService;
  final LocalePlaceMapping? _localeMapping;
  final SearchWorker _searchWorker;
  Future<void> _serializedReferenceSearch = Future.value();
  Future<void> _serializedUserSearch = Future.value();
  int _searchVersion = 0;

  /// Cancels any in-flight search call.
  ///
  /// Queued operations continue draining on the DB connection, but higher-level
  /// search steps stop scheduling further work as soon as they notice the
  /// version change.
  void cancelCurrentSearch() => _searchVersion++;

  SearchRepository({
    Database? database,
    Database? userDatabase,
    INaturalistService? iNatService,
    LocalePlaceMapping? localeMapping,
    SearchWorker? searchWorker,
  }) : _injectedReferenceDb = database,
       _injectedUserDb = userDatabase,
       _iNatService = iNatService,
       _localeMapping = localeMapping,
       _searchWorker = searchWorker ?? SearchWorker();

  /// Injects the device country's regional name preference into [sql].
  ///
  /// Two patterns are handled:
  ///   1. `ORDER BY (cn.country IS NULL) DESC` → country first, then global
  ///      (see [withCountryPreference], shared with the other catalog
  ///      repositories)
  ///   2. `AND cn2.country IS NULL ORDER BY` → remove global-only filter,
  ///      add regional ORDER BY instead (specific to this file's queries)
  ///
  /// No-op when [_localeMapping] is null (unknown region).
  String _withCountry(String sql) {
    final country = sqlSafeCountryCode(_localeMapping?.countryCodeNumeric);
    final withCountry = withCountryPreference(sql, country);
    if (country == null) return withCountry;
    return withCountry.replaceAll(
      'AND cn2.country IS NULL ORDER BY cn2.is_preferred DESC',
      "ORDER BY (cn2.country = '$country') DESC, (cn2.country IS NULL) DESC, cn2.is_preferred DESC",
    );
  }

  Future<Database> get _referenceDatabase async =>
      _injectedReferenceDb ?? await DatabaseHelper.referenceDb;

  Future<Database?> get _userDatabase async {
    if (_injectedReferenceDb != null && _injectedUserDb == null) {
      return null;
    }
    return _injectedUserDb ?? await DatabaseHelper.userDb;
  }

  Future<List<SearchResult>> searchAll(String term) async {
    final trimmedTerm = term.trim();
    if (trimmedTerm.isEmpty) return [];

    final myVersion = _searchVersion;
    bool isAbandoned() => _searchVersion != myVersion;

    final wildcardTerm = '$trimmedTerm*';
    final normalizedTerm =
        RuntimeCommonNameSearchRepository.normalizeSearchText(trimmedTerm);
    _logDebug('Search: query="$trimmedTerm"');

    final localResults = await Future.wait([
      _searchReferenceFts(wildcardTerm, isAbandoned: isAbandoned),
      _searchRuntimeCommonNameFtsSafely(wildcardTerm, isAbandoned),
    ]);
    if (isAbandoned()) return [];

    final referenceRows = localResults[0];
    final runtimeCommonNameRows = await _resolveRuntimeTaxonomyReferenceRows(
      localResults[1],
    );
    final referenceFallbackRows = await _searchReferenceFallbackIfNeeded(
      rawTerm: trimmedTerm,
      existingRows: [...referenceRows, ...runtimeCommonNameRows],
      isAbandoned: isAbandoned,
    );
    if (isAbandoned()) return [];

    final inatRows = referenceRows.isEmpty && runtimeCommonNameRows.isEmpty
        ? await _searchInat(trimmedTerm)
        : const <Map<String, dynamic>>[];
    if (isAbandoned()) return [];

    _logDebug(
      'Search: reference FTS=${referenceRows.length}, '
      'runtime common-name FTS=${runtimeCommonNameRows.length}, '
      'iNat=${inatRows.length}, '
      'reference LIKE=${referenceFallbackRows.length}',
    );

    final fallbackRows = await _resolveRuntimeTaxonomyReferenceRows(
      await _searchRuntimeCommonNameFallbackIfNeededSafely(
        normalizedTerm: normalizedTerm,
        existingRows: [
          ...referenceRows,
          ...runtimeCommonNameRows,
          ...inatRows,
          ...referenceFallbackRows,
        ],
        isAbandoned: isAbandoned,
      ),
    );
    if (isAbandoned()) return [];

    final workerResponse = await _searchWorker.process(
      SearchWorkerRequest(
        generation: myVersion,
        normalizedSearchTerm: normalizedTerm,
        referenceRows: referenceRows,
        downloadedRows: runtimeCommonNameRows,
        fallbackRows: fallbackRows,
        inatRows: inatRows,
        referenceFallbackRows: referenceFallbackRows,
      ),
    );
    if (isAbandoned() || workerResponse.isStale) return [];

    _logDebug('Search: merged=${workerResponse.results.length} results');
    return workerResponse.results;
  }

  /// Lightweight search path for live suggestions while the user is typing.
  ///
  /// This intentionally avoids user-DB lookups, iNaturalist requests, and
  /// higher-rank/taxonomy expansion so the UI stays responsive even during
  /// rapid query changes. It also skips the expensive reference LIKE fallback,
  /// which is better suited for the full search path once the user pauses or
  /// explicitly submits the query.
  Future<List<SearchResult>> searchQuick(String term) async {
    final trimmedTerm = term.trim();
    if (trimmedTerm.isEmpty) return [];

    final myVersion = _searchVersion;
    bool isAbandoned() => _searchVersion != myVersion;

    final quickSearchTerm = _quickSearchTerm(trimmedTerm);
    final quickSearchQuery = _quickSearchQuery(quickSearchTerm);
    final normalizedTerm =
        RuntimeCommonNameSearchRepository.normalizeSearchText(trimmedTerm);

    return _runSerializedReferenceSearch(
      () async {
        final referenceRows = await _searchReferenceSpeciesFts(
          quickSearchQuery,
          isAbandoned: isAbandoned,
        );
        if (isAbandoned()) return <SearchResult>[];

        final workerResponse = await _searchWorker.process(
          SearchWorkerRequest(
            generation: myVersion,
            normalizedSearchTerm: normalizedTerm,
            referenceRows: referenceRows,
          ),
        );
        if (isAbandoned() || workerResponse.isStale) {
          return const <SearchResult>[];
        }

        return workerResponse.results;
      },
      isAbandoned: isAbandoned,
      abandonedValue: const <SearchResult>[],
    );
  }

  String _quickSearchTerm(String term) {
    final tokens = term
        .trim()
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .toList();
    if (tokens.length <= 2) return tokens.join(' ');
    return tokens.sublist(tokens.length - 2).join(' ');
  }

  String _quickSearchQuery(String term) {
    final tokens = term
        .trim()
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .toList();
    if (tokens.length <= 1) return '${tokens.join(' ')}*';
    return tokens.join(' ');
  }

  Future<List<Map<String, dynamic>>> _searchReferenceSpeciesFts(
    String wildcardTerm, {
    required bool Function() isAbandoned,
  }) async {
    _logDebug('Search: querying reference DB (species FTS) "$wildcardTerm"');
    final db = await _referenceDatabase;
    if (isAbandoned()) return const [];

    try {
      final rows = await db.rawQuery(
        '''
          SELECT s.id,
                 g.name || ' ' || s.name AS scientific_name,
                 'species' AS entity_type
          FROM species s
          JOIN genera g ON g.id = s.genus
          WHERE s.status = 'active'
            AND s.id IN (SELECT id FROM species_fts WHERE species_fts MATCH ?)
          LIMIT $_referenceResultLimit
        ''',
        [wildcardTerm],
      );
      if (rows.isEmpty || isAbandoned()) return const [];
      final commonNames = await _bulkFetchCommonNames(
        db,
        rows.map((r) => r['id'] as String).toList(),
      );
      return _enrichWithCommonNames(rows, commonNames);
    } on DatabaseException {
      return const [];
    }
  }

  Future<List<SearchResult>> searchOnline(String term) async {
    final trimmedTerm = term.trim();
    if (trimmedTerm.isEmpty) return [];

    final myVersion = _searchVersion;
    bool isAbandoned() => _searchVersion != myVersion;

    final normalizedTerm =
        RuntimeCommonNameSearchRepository.normalizeSearchText(trimmedTerm);
    final inatRows = await _searchInat(trimmedTerm);
    if (isAbandoned()) return [];

    final workerResponse = await _searchWorker.process(
      SearchWorkerRequest(
        generation: myVersion,
        normalizedSearchTerm: normalizedTerm,
        inatRows: inatRows,
      ),
    );
    if (isAbandoned() || workerResponse.isStale) return [];
    return workerResponse.results;
  }

  Future<List<Map<String, dynamic>>> _searchReferenceFts(
    String wildcardTerm, {
    required bool Function() isAbandoned,
  }) async {
    _logDebug('Search: querying reference DB (FTS) "$wildcardTerm"');
    final db = await _referenceDatabase;

    // Two-phase search: Phase 1 finds entity IDs via FTS, Phase 2 bulk-fetches
    // their common names. This replaces the old approach of N×4 correlated
    // common-name subqueries per FTS result row.
    //
    // Phase 1 is a single UNION ALL across 9 FTS sub-queries (5 scientific-name
    // tables + 4 common-name lookups), so sqflite performs one DB round-trip
    // instead of 9. This prevents queue stacking when rapid typing launches
    // multiple concurrent searches on the same sqflite connection.
    //
    // IMPORTANT — query planner workaround:
    // Every FTS lookup uses `WHERE id IN (SELECT id FROM *_fts WHERE MATCH ?)`
    // instead of `FROM *_fts JOIN entity ON ...`. With a direct JOIN, SQLite's
    // planner starts from the entity table (scanning 138K+ species via
    // idx_species_status) and checks each row against the FTS virtual table,
    // resulting in 20–100+ second queries. The IN-subquery form forces it to
    // evaluate FTS first (typically returning a handful of rowids), then look
    // up only those specific entities — bringing query time to < 300 ms even
    // on low-end Android devices.
    final phase1Sql =
        '''
      SELECT id, scientific_name, entity_type FROM (
        SELECT s.id AS id, g.name || ' ' || s.name AS scientific_name, 'species' AS entity_type
        FROM species s
        JOIN genera g ON g.id = s.genus
        WHERE s.status = 'active'
          AND s.id IN (SELECT id FROM species_fts WHERE species_fts MATCH ?)
        LIMIT $_referenceResultLimit
      )
      UNION ALL
      SELECT id, scientific_name, entity_type FROM (
        SELECT s.id AS id, g.name || ' ' || s.name AS scientific_name, 'species' AS entity_type
        FROM species s
        JOIN genera g ON g.id = s.genus
        WHERE s.status = 'active'
          AND s.id IN (
            SELECT cn.entity_id FROM common_names cn
            WHERE cn.rowid IN (SELECT rowid FROM common_names_fts WHERE common_names_fts MATCH ?)
              AND cn.entity_type = 'species'
          )
        LIMIT $_referenceResultLimit
      )
      UNION ALL
      SELECT id, scientific_name, entity_type FROM (
        SELECT id AS id, name AS scientific_name, 'genera' AS entity_type
        FROM genera
        WHERE id IN (SELECT id FROM genera_fts WHERE genera_fts MATCH ?)
        LIMIT $_referenceResultLimit
      )
      UNION ALL
      SELECT id, scientific_name, entity_type FROM (
        SELECT g.id AS id, g.name AS scientific_name, 'genera' AS entity_type
        FROM genera g
        WHERE g.id IN (
          SELECT cn.entity_id FROM common_names cn
          WHERE cn.rowid IN (SELECT rowid FROM common_names_fts WHERE common_names_fts MATCH ?)
            AND cn.entity_type = 'genus'
        )
        LIMIT $_referenceResultLimit
      )
      UNION ALL
      SELECT id, scientific_name, entity_type FROM (
        SELECT id AS id, name AS scientific_name, 'families' AS entity_type
        FROM families
        WHERE id IN (SELECT id FROM families_fts WHERE families_fts MATCH ?)
        LIMIT $_referenceResultLimit
      )
      UNION ALL
      SELECT id, scientific_name, entity_type FROM (
        SELECT f.id AS id, f.name AS scientific_name, 'families' AS entity_type
        FROM families f
        WHERE f.id IN (
          SELECT cn.entity_id FROM common_names cn
          WHERE cn.rowid IN (SELECT rowid FROM common_names_fts WHERE common_names_fts MATCH ?)
            AND cn.entity_type = 'family'
        )
        LIMIT $_referenceResultLimit
      )
      UNION ALL
      SELECT id, scientific_name, entity_type FROM (
        SELECT id AS id, name AS scientific_name, 'orders' AS entity_type
        FROM orders
        WHERE id IN (SELECT id FROM orders_fts WHERE orders_fts MATCH ?)
        LIMIT $_referenceResultLimit
      )
      UNION ALL
      SELECT id, scientific_name, entity_type FROM (
        SELECT o.id AS id, o.name AS scientific_name, 'orders' AS entity_type
        FROM orders o
        WHERE o.id IN (
          SELECT cn.entity_id FROM common_names cn
          WHERE cn.rowid IN (SELECT rowid FROM common_names_fts WHERE common_names_fts MATCH ?)
            AND cn.entity_type = 'order'
        )
        LIMIT $_referenceResultLimit
      )
      UNION ALL
      SELECT id, scientific_name, entity_type FROM (
        SELECT id AS id, name AS scientific_name, 'classes' AS entity_type
        FROM classes
        WHERE id IN (SELECT id FROM classes_fts WHERE classes_fts MATCH ?)
        LIMIT $_referenceResultLimit
      )
    ''';

    final rawById = <String, Map<String, dynamic>>{};
    if (!isAbandoned()) {
      try {
        final rows = await db.rawQuery(phase1Sql, List.filled(9, wildcardTerm));
        for (final row in rows) {
          rawById.putIfAbsent(row['id'] as String, () => row);
        }
      } on DatabaseException {
        // FTS query failed; fall through to empty result
      }
    }

    if (rawById.isEmpty || isAbandoned()) return const [];

    // Phase 2: one bulk query for all matched entity IDs — replaces N×4 correlated subqueries.
    final commonNames = await _bulkFetchCommonNames(db, rawById.keys.toList());
    return _enrichWithCommonNames(rawById.values.toList(), commonNames);
  }

  Future<List<Map<String, dynamic>>> _searchInat(String term) async {
    if (_iNatService == null) return const [];

    _logDebug('Search: querying iNat for "$term"');

    final inatResults = await _iNatService.searchTaxa(term);

    _logDebug('Search: iNat API returned ${inatResults.length} taxa');

    if (inatResults.isEmpty) return const [];

    final speciesScientificNames = inatResults
        .where((result) => _isSpeciesRank(result['rank'] as String?))
        .map((result) => result['scientific_name'] as String)
        .where((name) => name.isNotEmpty)
        .toList();
    final taxonomyNamesByType = <String, Set<String>>{
      'genera': {},
      'families': {},
      'orders': {},
      'classes': {},
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
      _lookupTaxonomyByScientificNames(
        taxonomyNamesByType['genera']!.toList(),
        entityType: 'genera',
      ),
      _lookupTaxonomyByScientificNames(
        taxonomyNamesByType['families']!.toList(),
        entityType: 'families',
      ),
      _lookupTaxonomyByScientificNames(
        taxonomyNamesByType['orders']!.toList(),
        entityType: 'orders',
      ),
      _lookupTaxonomyByScientificNames(
        taxonomyNamesByType['classes']!.toList(),
        entityType: 'classes',
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

    // Enrich reference rows with the iNat preferred common name (EN fallback).
    return referenceMatches.map((row) {
      final nameKey = (row['scientific_name'] as String).toLowerCase();
      final inatPreferred = inatCommonNames[nameKey];
      if (inatPreferred == null) return row;

      final enriched = Map<String, dynamic>.from(row);
      final existingEn = (enriched['common_name_en'] as String?) ?? '';
      if (existingEn.trim().isEmpty) {
        enriched['common_name_en'] = inatPreferred;
      } else if (!existingEn.toLowerCase().contains(
        inatPreferred.toLowerCase(),
      )) {
        enriched['common_name_en'] = '$existingEn;$inatPreferred';
      }
      return enriched;
    }).toList()..addAll(directTaxonomyFallbackRows);
  }

  bool _isSpeciesRank(String? rank) =>
      rank == 'species' || rank == 'subspecies';

  String? _entityTypeForINatRank(String? rank) {
    switch (rank) {
      case 'genus':
        return 'genera';
      case 'family':
        return 'families';
      case 'order':
        return 'orders';
      case 'class':
        return 'classes';
      default:
        return null;
    }
  }

  Future<List<Map<String, dynamic>>> _lookupSpeciesByScientificNames(
    List<String> scientificNames,
  ) async {
    if (scientificNames.isEmpty) return const [];
    final db = await _referenceDatabase;
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
              _withCountry('''
        SELECT s.id,
               g.name || ' ' || s.name AS scientific_name,
               ${commonNameSubquery(entityAlias: 's', entityIdColumn: 'id', language: 'en', outputAlias: 'common_name_en')},
               ${commonNameSubquery(entityAlias: 's', entityIdColumn: 'id', language: 'de', outputAlias: 'common_name_de')},
               ${commonNameSubquery(entityAlias: 's', entityIdColumn: 'id', language: 'fr', outputAlias: 'common_name_fr')},
               ${commonNameSubquery(entityAlias: 's', entityIdColumn: 'id', language: 'es', outputAlias: 'common_name_es')},
               'species' AS entity_type
        FROM species s
        JOIN genera g ON g.id = s.genus
        WHERE lower(trim(g.name)) = ?
          AND lower(trim(s.name)) = ?
          AND s.status = 'active'
        LIMIT 1
      '''),
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

    final db = await _referenceDatabase;
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
              _withCountry('''
        SELECT t.id,
               t.name AS scientific_name,
               ${commonNameSubquery(entityAlias: 't', entityIdColumn: 'id', language: 'en', outputAlias: 'common_name_en')},
               ${commonNameSubquery(entityAlias: 't', entityIdColumn: 'id', language: 'de', outputAlias: 'common_name_de')},
               ${commonNameSubquery(entityAlias: 't', entityIdColumn: 'id', language: 'fr', outputAlias: 'common_name_fr')},
               ${commonNameSubquery(entityAlias: 't', entityIdColumn: 'id', language: 'es', outputAlias: 'common_name_es')},
               '$entityType' AS entity_type
        FROM $tableName t
        WHERE lower(trim(t.name)) IN ($placeholders)
        LIMIT $_referenceResultLimit
      '''),
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
    switch (entityType) {
      case 'genera':
        return 'genera';
      case 'families':
        return 'families';
      case 'orders':
        return 'orders';
      case 'classes':
        return 'classes';
      default:
        throw ArgumentError('Unsupported entity type: $entityType');
    }
  }

  Future<List<Map<String, dynamic>>> _resolveRuntimeTaxonomyReferenceRows(
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

  bool _isReferenceTaxonomyType(String entityType) {
    switch (entityType) {
      case 'genera':
      case 'families':
      case 'orders':
      case 'classes':
        return true;
      default:
        return false;
    }
  }

  Future<Map<String, String>> _lookupTaxonomyReferenceIds({
    required String entityType,
    required List<String> normalizedNames,
  }) async {
    if (normalizedNames.isEmpty) return const {};

    final db = await _referenceDatabase;
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

  Future<List<Map<String, dynamic>>> _searchReferenceFallbackIfNeeded({
    required String rawTerm,
    required List<Map<String, dynamic>> existingRows,
    required bool Function() isAbandoned,
  }) async {
    if (rawTerm.trim().isEmpty || existingRows.isNotEmpty) return const [];

    final db = await _referenceDatabase;
    final likeTerm = '%${rawTerm.trim()}%';
    final results = <Map<String, dynamic>>[];

    final phase1Queries = <(String, List<Object?>)>[
      (
        '''
          SELECT s.id, g.name || ' ' || s.name AS scientific_name, 'species' AS entity_type
          FROM species s
          JOIN genera g ON g.id = s.genus
          WHERE s.status = 'active'
            AND (
              lower(g.name || ' ' || s.name) LIKE lower(?)
              OR EXISTS (SELECT 1 FROM common_names cn WHERE cn.entity_id = s.id AND lower(cn.name) LIKE lower(?))
            )
          LIMIT $_referenceResultLimit
        ''',
        [likeTerm, likeTerm],
      ),
      (
        '''
          SELECT id, name AS scientific_name, 'genera' AS entity_type
          FROM genera t
          WHERE lower(t.name) LIKE lower(?)
             OR EXISTS (SELECT 1 FROM common_names cn WHERE cn.entity_id = t.id AND lower(cn.name) LIKE lower(?))
          LIMIT $_referenceResultLimit
        ''',
        [likeTerm, likeTerm],
      ),
      (
        '''
          SELECT id, name AS scientific_name, 'families' AS entity_type
          FROM families t
          WHERE lower(t.name) LIKE lower(?)
             OR EXISTS (SELECT 1 FROM common_names cn WHERE cn.entity_id = t.id AND lower(cn.name) LIKE lower(?))
          LIMIT $_referenceResultLimit
        ''',
        [likeTerm, likeTerm],
      ),
      (
        '''
          SELECT id, name AS scientific_name, 'orders' AS entity_type
          FROM orders t
          WHERE lower(t.name) LIKE lower(?)
             OR EXISTS (SELECT 1 FROM common_names cn WHERE cn.entity_id = t.id AND lower(cn.name) LIKE lower(?))
          LIMIT $_referenceResultLimit
        ''',
        [likeTerm, likeTerm],
      ),
      (
        '''
          SELECT id, name AS scientific_name, 'classes' AS entity_type
          FROM classes t
          WHERE lower(t.name) LIKE lower(?)
             OR EXISTS (SELECT 1 FROM common_names cn WHERE cn.entity_id = t.id AND lower(cn.name) LIKE lower(?))
          LIMIT $_referenceResultLimit
        ''',
        [likeTerm, likeTerm],
      ),
    ];

    final rawById = <String, Map<String, dynamic>>{};
    for (final (sql, args) in phase1Queries) {
      if (isAbandoned()) return results;
      try {
        final rows = await db.rawQuery(sql, args);
        for (final row in rows) {
          rawById.putIfAbsent(row['id'] as String, () => row);
        }
      } on DatabaseException {
        // continue with remaining tables
      }
    }

    if (rawById.isEmpty || isAbandoned()) return results;

    final commonNames = await _bulkFetchCommonNames(db, rawById.keys.toList());
    return _enrichWithCommonNames(rawById.values.toList(), commonNames);
  }

  Future<List<Map<String, dynamic>>> _searchRuntimeCommonNameFts(
    String wildcardTerm,
  ) async {
    _logDebug(
      'Search: querying runtime common-name search DB (FTS) "$wildcardTerm"',
    );
    final stopwatch = Stopwatch()..start();
    final userDb = await _userDatabase;
    if (userDb == null) {
      _logDebug(
        'Search: no user DB available, skipping runtime common-name FTS',
      );
      return [];
    }

    try {
      final rows = await userDb
          .rawQuery(
            '''
      SELECT d.entity_key AS id,
             d.entity_id,
             d.entity_type,
             d.scientific_name,
             d.common_name_en,
             d.common_name_de,
             d.common_name_fr,
             d.common_name_es
      FROM runtime_common_name_search_documents d
      JOIN runtime_common_name_search_fts f ON f.rowid = d.rowid
      WHERE runtime_common_name_search_fts MATCH ?
      LIMIT $_runtimeCommonNameResultLimit
    ''',
            [wildcardTerm],
          )
          .timeout(_referenceSearchTimeout, onTimeout: () => const []);
      _logDebug(
        'Search: runtime common-name FTS done "$wildcardTerm" '
        '(${rows.length} rows, ${stopwatch.elapsedMilliseconds}ms)',
      );
      return rows;
    } finally {
      stopwatch.stop();
    }
  }

  Future<List<Map<String, dynamic>>> _searchRuntimeCommonNameFtsSafely(
    String wildcardTerm,
    bool Function() isAbandoned,
  ) async {
    return _runSerializedUserSearch(() async {
      try {
        return await _searchRuntimeCommonNameFts(wildcardTerm);
      } on DatabaseException catch (e) {
        _logDebug('Search: runtime common-name FTS error: $e');
        return [];
      }
    }, isAbandoned: isAbandoned);
  }

  Future<List<Map<String, dynamic>>> _searchRuntimeCommonNameFallbackIfNeeded({
    required String normalizedTerm,
    required List<Map<String, dynamic>> existingRows,
  }) async {
    if (normalizedTerm.isEmpty || existingRows.length >= _fallbackThreshold) {
      return [];
    }

    final stopwatch = Stopwatch()..start();
    final userDb = await _userDatabase;
    if (userDb == null) return [];

    try {
      final rows = await userDb.rawQuery(
        '''
      SELECT entity_key AS id,
             entity_id,
             entity_type,
             scientific_name,
             common_name_en,
             common_name_de,
             common_name_fr,
             common_name_es
      FROM ${RuntimeCommonNameSearchRepository.documentsTable}
      WHERE normalized_search_text LIKE ? OR normalized_search_text LIKE ?
      LIMIT $_runtimeCommonNameResultLimit
    ''',
        ['$normalizedTerm%', '%$normalizedTerm%'],
      );
      _logDebug(
        'Search: runtime common-name fallback done "$normalizedTerm" '
        '(${rows.length} rows, ${stopwatch.elapsedMilliseconds}ms)',
      );
      return rows;
    } finally {
      stopwatch.stop();
    }
  }

  Future<List<Map<String, dynamic>>>
  _searchRuntimeCommonNameFallbackIfNeededSafely({
    required String normalizedTerm,
    required List<Map<String, dynamic>> existingRows,
    required bool Function() isAbandoned,
  }) async {
    return _runSerializedUserSearch(() async {
      try {
        return await _searchRuntimeCommonNameFallbackIfNeeded(
          normalizedTerm: normalizedTerm,
          existingRows: existingRows,
        );
      } on DatabaseException {
        return [];
      }
    }, isAbandoned: isAbandoned);
  }

  Future<T> _runSerializedUserSearch<T>(
    Future<T> Function() action, {
    required bool Function() isAbandoned,
  }) {
    final completer = Completer<void>();
    final previousSearch = _serializedUserSearch;
    _serializedUserSearch = completer.future;

    return (() async {
      await previousSearch;
      try {
        if (isAbandoned()) return [] as T;
        _logDebug('Search: serialized user search start');
        return await action();
      } finally {
        _logDebug('Search: serialized user search done');
        if (!completer.isCompleted) {
          completer.complete();
        }
      }
    })();
  }

  Future<T> _runSerializedReferenceSearch<T>(
    Future<T> Function() action, {
    required bool Function() isAbandoned,
    required T abandonedValue,
  }) {
    final completer = Completer<void>();
    final previousSearch = _serializedReferenceSearch;
    _serializedReferenceSearch = completer.future;

    return (() async {
      await previousSearch;
      try {
        if (isAbandoned()) return abandonedValue;
        _logDebug('Search: serialized reference search start');
        return await action();
      } finally {
        _logDebug('Search: serialized reference search done');
        if (!completer.isCompleted) {
          completer.complete();
        }
      }
    })();
  }

  /// Fetches the best common name per language for each entity in [entityIds]
  /// in a single bulk query, applying regional preference when available.
  ///
  /// Returns `entityId → language → name`. Uses `??=` on the sorted result
  /// so the first (= highest-priority) row per (entityId, language) wins.
  Future<Map<String, Map<String, String>>> _bulkFetchCommonNames(
    Database db,
    List<String> entityIds,
  ) async {
    if (entityIds.isEmpty) return const {};

    final country = sqlSafeCountryCode(_localeMapping?.countryCodeNumeric);
    final placeholders = List.filled(entityIds.length, '?').join(',');
    final orderBy = country != null
        ? "(country = '$country') DESC, (country IS NULL) DESC, is_preferred DESC, rank ASC"
        : '(country IS NULL) DESC, is_preferred DESC, rank ASC';

    final rows = await db.rawQuery('''
      SELECT entity_id, language, name
      FROM common_names
      WHERE entity_id IN ($placeholders)
        AND language IN ('de', 'en', 'fr', 'es')
      ORDER BY entity_id, language, $orderBy
      ''', entityIds);

    final result = <String, Map<String, String>>{};
    for (final row in rows) {
      final entityId = row['entity_id'] as String;
      final language = row['language'] as String;
      final name = row['name'] as String;
      (result[entityId] ??= {})[language] ??= name;
    }
    return result;
  }

  /// Merges common names from [commonNames] into [rows].
  List<Map<String, dynamic>> _enrichWithCommonNames(
    List<Map<String, dynamic>> rows,
    Map<String, Map<String, String>> commonNames,
  ) {
    return rows.map((row) {
      final names = commonNames[row['id'] as String];
      if (names == null) return row;
      return {
        ...row,
        'common_name_en': names['en'],
        'common_name_de': names['de'],
        'common_name_fr': names['fr'],
        'common_name_es': names['es'],
      };
    }).toList();
  }

  void _logDebug(String message) {
    if (_enableSearchDebugLogging) {
      _log.debug(message);
    }
  }
}
