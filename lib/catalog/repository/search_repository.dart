import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import 'package:discere/shared/external/inaturalist_service.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/catalog/model/locale_place_mapping.dart';
import 'package:discere/catalog/model/search_result.dart';
import 'package:discere/shared/persistence/database_helper.dart';
import 'package:discere/catalog/repository/runtime_common_name_search_repository.dart';

class SearchRepository {
  static const bool _enableSearchDebugLogging = true;
  static const Duration _referenceSearchTimeout = Duration(milliseconds: 1200);
  static const int _referenceResultLimit = 20;
  static const int _runtimeCommonNameResultLimit = 25;
  static const int _fallbackThreshold = 5;

  final Database? _injectedReferenceDb;
  final Database? _injectedUserDb;
  final INaturalistService? _iNatService;
  final LocalePlaceMapping? _localeMapping;
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
  }) : _injectedReferenceDb = database,
       _injectedUserDb = userDatabase,
       _iNatService = iNatService,
       _localeMapping = localeMapping;

  /// Injects the device country's regional name preference into [sql].
  ///
  /// Two patterns are handled:
  ///   1. `ORDER BY (cn.country IS NULL) DESC` → country first, then global
  ///   2. `AND cn2.country IS NULL ORDER BY` → remove global-only filter,
  ///      add regional ORDER BY instead
  ///
  /// No-op when [_localeMapping] is null (unknown region).
  String _withCountry(String sql) {
    final country = _localeMapping?.countryCodeNumeric;
    if (country == null) return sql;
    return sql
        .replaceAll(
          '(cn.country IS NULL) DESC',
          "(cn.country = '$country') DESC, (cn.country IS NULL) DESC",
        )
        .replaceAll(
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
    final runtimeCommonNameRows = localResults[1];
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

    final fallbackRows = await _searchRuntimeCommonNameFallbackIfNeededSafely(
      normalizedTerm: normalizedTerm,
      existingRows: [
        ...referenceRows,
        ...runtimeCommonNameRows,
        ...inatRows,
        ...referenceFallbackRows,
      ],
      isAbandoned: isAbandoned,
    );
    if (isAbandoned()) return [];

    final mergedCandidates = _mergeCandidates(
      _buildCandidates(
        normalizedSearchTerm: normalizedTerm,
        referenceRows: referenceRows,
        downloadedRows: runtimeCommonNameRows,
        fallbackRows: fallbackRows,
        inatRows: inatRows,
        referenceFallbackRows: referenceFallbackRows,
      ),
    );

    mergedCandidates.sort(_compareCandidates);
    _logDebug('Search: merged=${mergedCandidates.length} results');
    return mergedCandidates.map(_toSearchResult).toList();
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

        final mergedCandidates = _mergeCandidates(
          _buildCandidates(
            normalizedSearchTerm: normalizedTerm,
            referenceRows: referenceRows,
            downloadedRows: const [],
            fallbackRows: const [],
            inatRows: const [],
            referenceFallbackRows: const [],
          ),
        );

        mergedCandidates.sort(_compareCandidates);
        return mergedCandidates.map(_toSearchResult).toList();
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
      return await db.rawQuery(
        _withCountry('''
          SELECT s.id,
                 g.name || ' ' || s.name AS scientific_name,
                 (SELECT cn.name FROM common_names cn WHERE cn.entity_id = s.id AND cn.language = 'en' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 1) AS common_name_en,
                 (SELECT cn.name FROM common_names cn WHERE cn.entity_id = s.id AND cn.language = 'de' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 1) AS common_name_de,
                 (SELECT cn.name FROM common_names cn WHERE cn.entity_id = s.id AND cn.language = 'fr' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 1) AS common_name_fr,
                 (SELECT cn.name FROM common_names cn WHERE cn.entity_id = s.id AND cn.language = 'es' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 1) AS common_name_es,
                 'species' AS entity_type
          FROM species_fts sf
          JOIN species s ON s.id = sf.id
          JOIN genera g ON g.id = s.genus
          WHERE species_fts MATCH ? AND s.status = 'active'
          LIMIT $_referenceResultLimit
        '''),
        [wildcardTerm],
      );
    } on DatabaseException {
      return const [];
    }
  }

  List<_SearchCandidate> _buildCandidates({
    required String normalizedSearchTerm,
    required List<Map<String, dynamic>> referenceRows,
    required List<Map<String, dynamic>> downloadedRows,
    required List<Map<String, dynamic>> fallbackRows,
    required List<Map<String, dynamic>> inatRows,
    required List<Map<String, dynamic>> referenceFallbackRows,
  }) {
    return [
      ...referenceRows.map(
        (row) => _candidateFromReferenceRow(
          row,
          normalizedSearchTerm: normalizedSearchTerm,
        ),
      ),
      ...downloadedRows.map(
        (row) => _candidateFromDownloadedRow(
          row,
          normalizedSearchTerm: normalizedSearchTerm,
        ),
      ),
      ...fallbackRows.map(
        (row) => _candidateFromDownloadedRow(
          row,
          normalizedSearchTerm: normalizedSearchTerm,
          isFallback: true,
        ),
      ),
      ...inatRows.map(
        (row) => _candidateFromReferenceRow(
          row,
          normalizedSearchTerm: normalizedSearchTerm,
          sourcePriority: 0,
        ),
      ),
      ...referenceFallbackRows.map(
        (row) => _candidateFromReferenceRow(
          row,
          normalizedSearchTerm: normalizedSearchTerm,
          sourcePriority: 2,
        ),
      ),
    ];
  }

  Future<List<Map<String, dynamic>>> _searchReferenceFts(
    String wildcardTerm, {
    required bool Function() isAbandoned,
  }) async {
    _logDebug('Search: querying reference DB (FTS) "$wildcardTerm"');
    final db = await _referenceDatabase;
    final results = <Map<String, dynamic>>[];

    final queries = <(String, List<Object?>)>[
      // Species by scientific name
      (
        '''
          SELECT s.id,
                 g.name || ' ' || s.name AS scientific_name,
                 (SELECT cn.name FROM common_names cn WHERE cn.entity_id = s.id AND cn.language = 'en' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 1) AS common_name_en,
                 (SELECT cn.name FROM common_names cn WHERE cn.entity_id = s.id AND cn.language = 'de' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 1) AS common_name_de,
                 (SELECT cn.name FROM common_names cn WHERE cn.entity_id = s.id AND cn.language = 'fr' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 1) AS common_name_fr,
                 (SELECT cn.name FROM common_names cn WHERE cn.entity_id = s.id AND cn.language = 'es' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 1) AS common_name_es,
                 'species' AS entity_type
          FROM species_fts sf
          JOIN species s ON s.id = sf.id
          JOIN genera g ON g.id = s.genus
          WHERE species_fts MATCH ? AND s.status = 'active'
          LIMIT $_referenceResultLimit
        ''',
        [wildcardTerm],
      ),
      // Species by common name (common_names_fts)
      (
        '''
          SELECT DISTINCT s.id,
                 g.name || ' ' || s.name AS scientific_name,
                 (SELECT cn2.name FROM common_names cn2 WHERE cn2.entity_id = s.id AND cn2.language = 'en' AND cn2.country IS NULL ORDER BY cn2.is_preferred DESC, cn2.rank ASC LIMIT 1) AS common_name_en,
                 (SELECT cn2.name FROM common_names cn2 WHERE cn2.entity_id = s.id AND cn2.language = 'de' AND cn2.country IS NULL ORDER BY cn2.is_preferred DESC, cn2.rank ASC LIMIT 1) AS common_name_de,
                 (SELECT cn2.name FROM common_names cn2 WHERE cn2.entity_id = s.id AND cn2.language = 'fr' AND cn2.country IS NULL ORDER BY cn2.is_preferred DESC, cn2.rank ASC LIMIT 1) AS common_name_fr,
                 (SELECT cn2.name FROM common_names cn2 WHERE cn2.entity_id = s.id AND cn2.language = 'es' AND cn2.country IS NULL ORDER BY cn2.is_preferred DESC, cn2.rank ASC LIMIT 1) AS common_name_es,
                 'species' AS entity_type
          FROM common_names_fts cnf
          JOIN common_names cn ON cn.rowid = cnf.rowid
          JOIN species s ON s.id = cn.entity_id
          JOIN genera g ON g.id = s.genus
          WHERE common_names_fts MATCH ? AND cn.entity_type = 'species' AND s.status = 'active'
          LIMIT $_referenceResultLimit
        ''',
        [wildcardTerm],
      ),
      // Genera by scientific name
      (
        '''
          SELECT gf.id,
                 gf.name AS scientific_name,
                 (SELECT cn.name FROM common_names cn WHERE cn.entity_id = gf.id AND cn.language = 'en' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 1) AS common_name_en,
                 NULL AS common_name_de,
                 NULL AS common_name_fr,
                 NULL AS common_name_es,
                 'genera' AS entity_type
          FROM genera_fts gf
          WHERE genera_fts MATCH ?
          LIMIT $_referenceResultLimit
        ''',
        [wildcardTerm],
      ),
      // Genera by common name (common_names_fts)
      (
        '''
          SELECT DISTINCT g.id,
                 g.name AS scientific_name,
                 cn.name AS common_name_en,
                 NULL AS common_name_de,
                 NULL AS common_name_fr,
                 NULL AS common_name_es,
                 'genera' AS entity_type
          FROM common_names_fts cnf
          JOIN common_names cn ON cn.rowid = cnf.rowid
          JOIN genera g ON g.id = cn.entity_id
          WHERE common_names_fts MATCH ? AND cn.entity_type = 'genus'
          LIMIT $_referenceResultLimit
        ''',
        [wildcardTerm],
      ),
      // Families by scientific name
      (
        '''
          SELECT ff.id,
                 ff.name AS scientific_name,
                 (SELECT cn.name FROM common_names cn WHERE cn.entity_id = ff.id AND cn.language = 'en' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 1) AS common_name_en,
                 (SELECT cn.name FROM common_names cn WHERE cn.entity_id = ff.id AND cn.language = 'de' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 1) AS common_name_de,
                 (SELECT cn.name FROM common_names cn WHERE cn.entity_id = ff.id AND cn.language = 'fr' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 1) AS common_name_fr,
                 (SELECT cn.name FROM common_names cn WHERE cn.entity_id = ff.id AND cn.language = 'es' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 1) AS common_name_es,
                 'families' AS entity_type
          FROM families_fts ff
          WHERE families_fts MATCH ?
          LIMIT $_referenceResultLimit
        ''',
        [wildcardTerm],
      ),
      // Families by common name (common_names_fts)
      (
        '''
          SELECT DISTINCT f.id,
                 f.name AS scientific_name,
                 (SELECT cn2.name FROM common_names cn2 WHERE cn2.entity_id = f.id AND cn2.language = 'en' AND cn2.country IS NULL ORDER BY cn2.is_preferred DESC, cn2.rank ASC LIMIT 1) AS common_name_en,
                 (SELECT cn2.name FROM common_names cn2 WHERE cn2.entity_id = f.id AND cn2.language = 'de' AND cn2.country IS NULL ORDER BY cn2.is_preferred DESC, cn2.rank ASC LIMIT 1) AS common_name_de,
                 (SELECT cn2.name FROM common_names cn2 WHERE cn2.entity_id = f.id AND cn2.language = 'fr' AND cn2.country IS NULL ORDER BY cn2.is_preferred DESC, cn2.rank ASC LIMIT 1) AS common_name_fr,
                 (SELECT cn2.name FROM common_names cn2 WHERE cn2.entity_id = f.id AND cn2.language = 'es' AND cn2.country IS NULL ORDER BY cn2.is_preferred DESC, cn2.rank ASC LIMIT 1) AS common_name_es,
                 'families' AS entity_type
          FROM common_names_fts cnf
          JOIN common_names cn ON cn.rowid = cnf.rowid
          JOIN families f ON f.id = cn.entity_id
          WHERE common_names_fts MATCH ? AND cn.entity_type = 'family'
          LIMIT $_referenceResultLimit
        ''',
        [wildcardTerm],
      ),
      // Orders by scientific name
      (
        '''
          SELECT orf.id,
                 orf.name AS scientific_name,
                 (SELECT cn.name FROM common_names cn WHERE cn.entity_id = orf.id AND cn.language = 'en' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 1) AS common_name_en,
                 (SELECT cn.name FROM common_names cn WHERE cn.entity_id = orf.id AND cn.language = 'de' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 1) AS common_name_de,
                 (SELECT cn.name FROM common_names cn WHERE cn.entity_id = orf.id AND cn.language = 'fr' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 1) AS common_name_fr,
                 (SELECT cn.name FROM common_names cn WHERE cn.entity_id = orf.id AND cn.language = 'es' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 1) AS common_name_es,
                 'orders' AS entity_type
          FROM orders_fts orf
          WHERE orders_fts MATCH ?
          LIMIT $_referenceResultLimit
        ''',
        [wildcardTerm],
      ),
      // Orders by common name (common_names_fts)
      (
        '''
          SELECT DISTINCT o.id,
                 o.name AS scientific_name,
                 (SELECT cn2.name FROM common_names cn2 WHERE cn2.entity_id = o.id AND cn2.language = 'en' AND cn2.country IS NULL ORDER BY cn2.is_preferred DESC, cn2.rank ASC LIMIT 1) AS common_name_en,
                 (SELECT cn2.name FROM common_names cn2 WHERE cn2.entity_id = o.id AND cn2.language = 'de' AND cn2.country IS NULL ORDER BY cn2.is_preferred DESC, cn2.rank ASC LIMIT 1) AS common_name_de,
                 (SELECT cn2.name FROM common_names cn2 WHERE cn2.entity_id = o.id AND cn2.language = 'fr' AND cn2.country IS NULL ORDER BY cn2.is_preferred DESC, cn2.rank ASC LIMIT 1) AS common_name_fr,
                 (SELECT cn2.name FROM common_names cn2 WHERE cn2.entity_id = o.id AND cn2.language = 'es' AND cn2.country IS NULL ORDER BY cn2.is_preferred DESC, cn2.rank ASC LIMIT 1) AS common_name_es,
                 'orders' AS entity_type
          FROM common_names_fts cnf
          JOIN common_names cn ON cn.rowid = cnf.rowid
          JOIN orders o ON o.id = cn.entity_id
          WHERE common_names_fts MATCH ? AND cn.entity_type = 'order'
          LIMIT $_referenceResultLimit
        ''',
        [wildcardTerm],
      ),
      // Classes by scientific name
      (
        '''
          SELECT cf.id,
                 cf.name AS scientific_name,
                 (SELECT cn.name FROM common_names cn WHERE cn.entity_id = cf.id AND cn.language = 'en' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 1) AS common_name_en,
                 NULL AS common_name_de,
                 NULL AS common_name_fr,
                 NULL AS common_name_es,
                 'classes' AS entity_type
          FROM classes_fts cf
          WHERE classes_fts MATCH ?
          LIMIT $_referenceResultLimit
        ''',
        [wildcardTerm],
      ),
    ];

    for (final (sql, args) in queries) {
      if (isAbandoned()) return results;
      try {
        results.addAll(await db.rawQuery(_withCountry(sql), args));
      } on DatabaseException {
        // individual FTS table query failed; continue with remaining
      }
    }

    return results;
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

  Future<List<SearchResult>> searchOnline(String term) async {
    final trimmedTerm = term.trim();
    if (trimmedTerm.isEmpty) return [];

    final normalizedTerm =
        RuntimeCommonNameSearchRepository.normalizeSearchText(trimmedTerm);
    final inatRows = await _searchInat(trimmedTerm);
    final mergedCandidates = _mergeCandidates(
      _buildCandidates(
        normalizedSearchTerm: normalizedTerm,
        referenceRows: const [],
        downloadedRows: const [],
        fallbackRows: const [],
        inatRows: inatRows,
        referenceFallbackRows: const [],
      ),
    );

    mergedCandidates.sort(_compareCandidates);
    return mergedCandidates.map(_toSearchResult).toList();
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
               (SELECT cn.name FROM common_names cn WHERE cn.entity_id = s.id AND cn.language = 'en' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 1) AS common_name_en,
               (SELECT cn.name FROM common_names cn WHERE cn.entity_id = s.id AND cn.language = 'de' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 1) AS common_name_de,
               (SELECT cn.name FROM common_names cn WHERE cn.entity_id = s.id AND cn.language = 'fr' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 1) AS common_name_fr,
               (SELECT cn.name FROM common_names cn WHERE cn.entity_id = s.id AND cn.language = 'es' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 1) AS common_name_es,
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
            .rawQuery(_withCountry('''
        SELECT t.id,
               t.name AS scientific_name,
               (SELECT cn.name FROM common_names cn WHERE cn.entity_id = t.id AND cn.language = 'en' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 1) AS common_name_en,
               (SELECT cn.name FROM common_names cn WHERE cn.entity_id = t.id AND cn.language = 'de' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 1) AS common_name_de,
               (SELECT cn.name FROM common_names cn WHERE cn.entity_id = t.id AND cn.language = 'fr' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 1) AS common_name_fr,
               (SELECT cn.name FROM common_names cn WHERE cn.entity_id = t.id AND cn.language = 'es' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 1) AS common_name_es,
               '$entityType' AS entity_type
        FROM $tableName t
        WHERE lower(trim(t.name)) IN ($placeholders)
        LIMIT $_referenceResultLimit
      '''), chunk)
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

    final queries = <(String, List<Object?>)>[
      (
        '''
          SELECT s.id,
                 g.name || ' ' || s.name AS scientific_name,
                 (SELECT cn.name FROM common_names cn WHERE cn.entity_id = s.id AND cn.language = 'en' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 1) AS common_name_en,
                 (SELECT cn.name FROM common_names cn WHERE cn.entity_id = s.id AND cn.language = 'de' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 1) AS common_name_de,
                 (SELECT cn.name FROM common_names cn WHERE cn.entity_id = s.id AND cn.language = 'fr' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 1) AS common_name_fr,
                 (SELECT cn.name FROM common_names cn WHERE cn.entity_id = s.id AND cn.language = 'es' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 1) AS common_name_es,
                 'species' AS entity_type
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
          SELECT t.id,
                 t.name AS scientific_name,
                 (SELECT cn.name FROM common_names cn WHERE cn.entity_id = t.id AND cn.language = 'en' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 1) AS common_name_en,
                 NULL AS common_name_de,
                 NULL AS common_name_fr,
                 NULL AS common_name_es,
                 'genera' AS entity_type
          FROM genera t
          WHERE lower(t.name) LIKE lower(?)
             OR EXISTS (SELECT 1 FROM common_names cn WHERE cn.entity_id = t.id AND lower(cn.name) LIKE lower(?))
          LIMIT $_referenceResultLimit
        ''',
        [likeTerm, likeTerm],
      ),
      (
        '''
          SELECT t.id,
                 t.name AS scientific_name,
                 (SELECT cn.name FROM common_names cn WHERE cn.entity_id = t.id AND cn.language = 'en' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 1) AS common_name_en,
                 (SELECT cn.name FROM common_names cn WHERE cn.entity_id = t.id AND cn.language = 'de' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 1) AS common_name_de,
                 (SELECT cn.name FROM common_names cn WHERE cn.entity_id = t.id AND cn.language = 'fr' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 1) AS common_name_fr,
                 (SELECT cn.name FROM common_names cn WHERE cn.entity_id = t.id AND cn.language = 'es' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 1) AS common_name_es,
                 'families' AS entity_type
          FROM families t
          WHERE lower(t.name) LIKE lower(?)
             OR EXISTS (SELECT 1 FROM common_names cn WHERE cn.entity_id = t.id AND lower(cn.name) LIKE lower(?))
          LIMIT $_referenceResultLimit
        ''',
        [likeTerm, likeTerm],
      ),
      (
        '''
          SELECT t.id,
                 t.name AS scientific_name,
                 (SELECT cn.name FROM common_names cn WHERE cn.entity_id = t.id AND cn.language = 'en' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 1) AS common_name_en,
                 (SELECT cn.name FROM common_names cn WHERE cn.entity_id = t.id AND cn.language = 'de' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 1) AS common_name_de,
                 (SELECT cn.name FROM common_names cn WHERE cn.entity_id = t.id AND cn.language = 'fr' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 1) AS common_name_fr,
                 (SELECT cn.name FROM common_names cn WHERE cn.entity_id = t.id AND cn.language = 'es' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 1) AS common_name_es,
                 'orders' AS entity_type
          FROM orders t
          WHERE lower(t.name) LIKE lower(?)
             OR EXISTS (SELECT 1 FROM common_names cn WHERE cn.entity_id = t.id AND lower(cn.name) LIKE lower(?))
          LIMIT $_referenceResultLimit
        ''',
        [likeTerm, likeTerm],
      ),
      (
        '''
          SELECT t.id,
                 t.name AS scientific_name,
                 (SELECT cn.name FROM common_names cn WHERE cn.entity_id = t.id AND cn.language = 'en' ORDER BY (cn.country IS NULL) DESC, cn.is_preferred DESC, cn.rank ASC LIMIT 1) AS common_name_en,
                 NULL AS common_name_de,
                 NULL AS common_name_fr,
                 NULL AS common_name_es,
                 'classes' AS entity_type
          FROM classes t
          WHERE lower(t.name) LIKE lower(?)
             OR EXISTS (SELECT 1 FROM common_names cn WHERE cn.entity_id = t.id AND lower(cn.name) LIKE lower(?))
          LIMIT $_referenceResultLimit
        ''',
        [likeTerm, likeTerm],
      ),
    ];

    for (final (sql, args) in queries) {
      if (isAbandoned()) return results;
      try {
        results.addAll(await db.rawQuery(_withCountry(sql), args));
      } on DatabaseException {
        // continue with remaining tables
      }
    }

    return results;
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
      final rows = await userDb.rawQuery(
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
      );
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

  _SearchCandidate _candidateFromReferenceRow(
    Map<String, dynamic> row, {
    required String normalizedSearchTerm,
    int sourcePriority = 1,
  }) {
    return _SearchCandidate(
      stableKey: _stableKeyForEntity(
        entityType: row['entity_type'] as String,
        entityId: row['id'] as String,
        scientificName: row['scientific_name'] as String,
      ),
      id: row['id'] as String,
      name: row['scientific_name'] as String,
      commonNames: _commonNamesFromRow(row),
      type: _entityTypeFromString(row['entity_type'] as String),
      matchPriority: _matchPriorityFromRow(
        row,
        normalizedSearchTerm: normalizedSearchTerm,
        isFallback: false,
      ),
      sourcePriority: sourcePriority,
    );
  }

  _SearchCandidate _candidateFromDownloadedRow(
    Map<String, dynamic> row, {
    required String normalizedSearchTerm,
    bool isFallback = false,
  }) {
    final entityType = row['entity_type'] as String;
    final entityId = row['entity_id'] as String? ?? row['id'] as String;
    final scientificName = row['scientific_name'] as String;

    return _SearchCandidate(
      stableKey: _stableKeyForEntity(
        entityType: entityType,
        entityId: entityId,
        scientificName: scientificName,
      ),
      id: entityType == 'species'
          ? entityId
          : (row['id'] as String? ?? entityId),
      name: scientificName,
      commonNames: _commonNamesFromRow(row),
      type: _entityTypeFromString(entityType),
      matchPriority: _matchPriorityFromRow(
        row,
        normalizedSearchTerm: normalizedSearchTerm,
        isFallback: isFallback,
      ),
      sourcePriority: 0,
    );
  }

  List<_SearchCandidate> _mergeCandidates(List<_SearchCandidate> candidates) {
    final mergedByKey = <String, _SearchCandidate>{};

    for (final candidate in candidates) {
      final existing = mergedByKey[candidate.stableKey];
      if (existing == null) {
        mergedByKey[candidate.stableKey] = candidate;
        continue;
      }

      mergedByKey[candidate.stableKey] = existing.merge(candidate);
    }

    return mergedByKey.values.toList();
  }

  int _compareCandidates(_SearchCandidate a, _SearchCandidate b) {
    final matchCompare = a.matchPriority.compareTo(b.matchPriority);
    if (matchCompare != 0) return matchCompare;

    final localizedCompare = _localizedCommonNameWeight(
      b,
    ).compareTo(_localizedCommonNameWeight(a));
    if (localizedCompare != 0) return localizedCompare;

    final sourceCompare = a.sourcePriority.compareTo(b.sourcePriority);
    if (sourceCompare != 0) return sourceCompare;

    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  int _localizedCommonNameWeight(_SearchCandidate candidate) {
    if ((candidate.commonNames[Language.en] ?? '').trim().isNotEmpty) return 2;
    if (candidate.commonNames.values.any((value) => value.trim().isNotEmpty)) {
      return 1;
    }
    return 0;
  }

  SearchResult _toSearchResult(_SearchCandidate candidate) {
    return SearchResult(
      id: candidate.id,
      name: candidate.name,
      commonNames: {
        Language.en: _nullable(candidate.commonNames[Language.en] ?? ''),
        Language.de: _nullable(candidate.commonNames[Language.de] ?? ''),
        Language.fr: _nullable(candidate.commonNames[Language.fr] ?? ''),
        Language.es: _nullable(candidate.commonNames[Language.es] ?? ''),
      },
      type: candidate.type,
    );
  }

  Map<Language, String> _commonNamesFromRow(Map<String, dynamic> row) {
    return {
      Language.en: row['common_name_en'] as String? ?? '',
      Language.de: row['common_name_de'] as String? ?? '',
      Language.fr: row['common_name_fr'] as String? ?? '',
      Language.es: row['common_name_es'] as String? ?? '',
    };
  }

  int _matchPriorityFromRow(
    Map<String, dynamic> row, {
    required String normalizedSearchTerm,
    required bool isFallback,
  }) {
    if (normalizedSearchTerm.isEmpty) return isFallback ? 2 : 1;

    final searchableValues = <String>[
      row['scientific_name'] as String? ?? '',
      row['common_name_en'] as String? ?? '',
      row['common_name_de'] as String? ?? '',
      row['common_name_fr'] as String? ?? '',
      row['common_name_es'] as String? ?? '',
    ];

    final normalizedCandidates = searchableValues
        .expand((value) => value.split(';'))
        .map(RuntimeCommonNameSearchRepository.normalizeSearchText)
        .where((value) => value.isNotEmpty)
        .toList();

    if (normalizedCandidates.contains(normalizedSearchTerm)) {
      return 0;
    }
    if (normalizedCandidates.any(
      (value) => value.startsWith(normalizedSearchTerm),
    )) {
      return 1;
    }
    return isFallback ? 3 : 2;
  }

  String _stableKeyForEntity({
    required String entityType,
    required String entityId,
    required String scientificName,
  }) {
    if (entityType == 'species') {
      return 'species:$entityId';
    }
    return '$entityType:${scientificName.trim().toLowerCase()}';
  }

  SearchEntityType _entityTypeFromString(String entityType) {
    switch (entityType) {
      case 'species':
        return SearchEntityType.species;
      case 'genera':
        return SearchEntityType.genus;
      case 'families':
        return SearchEntityType.family;
      case 'orders':
        return SearchEntityType.order;
      case 'classes':
        return SearchEntityType.classType;
      default:
        throw Exception('Unknown entity type: $entityType');
    }
  }

  String? _nullable(String value) => value.trim().isEmpty ? null : value;

  void _logDebug(String message) {
    if (kDebugMode && _enableSearchDebugLogging) {
      debugPrint(message);
    }
  }
}

class _SearchCandidate {
  final String stableKey;
  final String id;
  final String name;
  final Map<Language, String> commonNames;
  final SearchEntityType type;
  final int matchPriority;
  final int sourcePriority;

  const _SearchCandidate({
    required this.stableKey,
    required this.id,
    required this.name,
    required this.commonNames,
    required this.type,
    required this.matchPriority,
    required this.sourcePriority,
  });

  _SearchCandidate merge(_SearchCandidate other) {
    final preferred = sourcePriority <= other.sourcePriority ? this : other;
    final secondary = identical(preferred, this) ? other : this;

    return _SearchCandidate(
      stableKey: stableKey,
      id: preferred.id,
      name: preferred.name.length >= secondary.name.length
          ? preferred.name
          : secondary.name,
      commonNames: {
        for (final language in Language.values)
          language: _mergeCommonNameStrings(
            preferred.commonNames[language] ?? '',
            secondary.commonNames[language] ?? '',
          ),
      },
      type: preferred.type,
      matchPriority: preferred.matchPriority <= secondary.matchPriority
          ? preferred.matchPriority
          : secondary.matchPriority,
      sourcePriority: preferred.sourcePriority,
    );
  }

  String _mergeCommonNameStrings(String primary, String secondary) {
    final merged = <String>[];
    final seen = <String>{};

    for (final source in [primary, secondary]) {
      final parts = source
          .split(';')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty);
      for (final part in parts) {
        final normalized = part
            .toLowerCase()
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        if (normalized.isEmpty || seen.contains(normalized)) continue;
        seen.add(normalized);
        merged.add(part);
      }
    }

    return merged.join(';');
  }
}
