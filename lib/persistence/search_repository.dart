import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../external/inaturalist/inaturalist_service.dart';
import '../model/language.dart';
import '../model/search/search_result.dart';
import 'database_helper.dart';
import 'downloaded_name_search_repository.dart';

class SearchRepository {
  static const bool _enableSearchDebugLogging = true;
  static const Duration _referenceSearchTimeout = Duration(milliseconds: 1200);
  static const Duration _userSearchTimeout = Duration(milliseconds: 800);
  static const int _referenceResultLimit = 20;
  static const int _downloadedResultLimit = 25;
  static const int _inatSearchThreshold = 1;
  static const int _fallbackThreshold = 5;

  final Database? _injectedReferenceDb;
  final Database? _injectedUserDb;
  final INaturalistService? _iNatService;
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
  }) : _injectedReferenceDb = database,
       _injectedUserDb = userDatabase,
       _iNatService = iNatService;

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
    final normalizedTerm = DownloadedNameSearchRepository.normalizeSearchText(
      trimmedTerm,
    );
    _logDebug('Search: query="$trimmedTerm"');

    final localResults = await Future.wait([
      _searchReferenceFts(wildcardTerm, isAbandoned: isAbandoned),
      _searchDownloadedFtsSafely(wildcardTerm, isAbandoned),
    ]);
    if (isAbandoned()) return [];

    final referenceRows = localResults[0];
    final downloadedRows = localResults[1];
    final shouldQueryINat = _shouldQueryINat(
      query: trimmedTerm,
      referenceRows: referenceRows,
      downloadedRows: downloadedRows,
    );
    final inatRows = shouldQueryINat
        ? await _searchInat(trimmedTerm)
        : const <Map<String, dynamic>>[];
    if (isAbandoned()) return [];

    final referenceFallbackRows = await _searchReferenceFallbackIfNeeded(
      rawTerm: trimmedTerm,
      existingRows: [...referenceRows, ...downloadedRows, ...inatRows],
      isAbandoned: isAbandoned,
    );
    if (isAbandoned()) return [];

    _logDebug(
      'Search: reference FTS=${referenceRows.length}, '
      'downloaded FTS=${downloadedRows.length}, '
      'iNat=${inatRows.length}, '
      'reference LIKE=${referenceFallbackRows.length}',
    );

    final fallbackRows = await _searchDownloadedFallbackIfNeededSafely(
      normalizedTerm: normalizedTerm,
      existingRows: [...referenceRows, ...downloadedRows, ...inatRows],
      isAbandoned: isAbandoned,
    );
    if (isAbandoned()) return [];

    final mergedCandidates = _mergeCandidates(
      _buildCandidates(
        normalizedSearchTerm: normalizedTerm,
        referenceRows: referenceRows,
        downloadedRows: downloadedRows,
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
  /// This intentionally avoids user-DB lookups and iNaturalist requests so the
  /// UI stays responsive even during rapid query changes.
  Future<List<SearchResult>> searchQuick(String term) async {
    final trimmedTerm = term.trim();
    if (trimmedTerm.isEmpty) return [];

    final myVersion = _searchVersion;
    bool isAbandoned() => _searchVersion != myVersion;

    final wildcardTerm = '$trimmedTerm*';
    final normalizedTerm = DownloadedNameSearchRepository.normalizeSearchText(
      trimmedTerm,
    );

    final referenceRows = await _searchReferenceFts(
      wildcardTerm,
      isAbandoned: isAbandoned,
    );
    if (isAbandoned()) return [];

    final referenceFallbackRows = await _searchReferenceFallbackIfNeeded(
      rawTerm: trimmedTerm,
      existingRows: referenceRows,
      isAbandoned: isAbandoned,
    );
    if (isAbandoned()) return [];

    final mergedCandidates = _mergeCandidates(
      _buildCandidates(
        normalizedSearchTerm: normalizedTerm,
        referenceRows: referenceRows,
        downloadedRows: const [],
        fallbackRows: const [],
        inatRows: const [],
        referenceFallbackRows: referenceFallbackRows,
      ),
    );

    mergedCandidates.sort(_compareCandidates);
    return mergedCandidates.map(_toSearchResult).toList();
  }

  bool _shouldQueryINat({
    required String query,
    required List<Map<String, dynamic>> referenceRows,
    required List<Map<String, dynamic>> downloadedRows,
  }) {
    return _iNatService != null &&
        query.length >= 3 &&
        (referenceRows.length + downloadedRows.length) < _inatSearchThreshold;
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
      (
        '''
          SELECT sf.id,
                 g.name || ' ' || sf.name AS scientific_name,
                 sf.common_name_en,
                 sf.common_name_de,
                 sf.common_name_fr,
                 sf.common_name_es,
                 'species' AS entity_type
          FROM species_fts sf
          JOIN species s ON s.id = sf.id
          JOIN genera g ON g.id = s.genus
          WHERE species_fts MATCH ? AND s.status = 'active'
          LIMIT $_referenceResultLimit
        ''',
        [wildcardTerm],
      ),
      (
        '''
          SELECT DISTINCT s.id,
                 g.name || ' ' || s.name AS scientific_name,
                 s.common_name_en,
                 s.common_name_de,
                 s.common_name_fr,
                 s.common_name_es,
                 'species' AS entity_type
          FROM species_names_fts snf
          JOIN species s ON s.id = snf.species_id
          JOIN genera g ON g.id = s.genus
          WHERE species_names_fts MATCH ? AND s.status = 'active'
          LIMIT $_referenceResultLimit
        ''',
        [wildcardTerm],
      ),
      (
        '''
          SELECT id,
                 name AS scientific_name,
                 NULL AS common_name_en,
                 NULL AS common_name_de,
                 NULL AS common_name_fr,
                 NULL AS common_name_es,
                 'genera' AS entity_type
          FROM genera_fts
          WHERE genera_fts MATCH ?
          LIMIT $_referenceResultLimit
        ''',
        [wildcardTerm],
      ),
      (
        '''
          SELECT id,
                 name AS scientific_name,
                 common_name_en,
                 common_name_de,
                 common_name_fr,
                 common_name_es,
                 'families' AS entity_type
          FROM families_fts
          WHERE families_fts MATCH ?
          LIMIT $_referenceResultLimit
        ''',
        [wildcardTerm],
      ),
      (
        '''
          SELECT id,
                 name AS scientific_name,
                 common_name_en,
                 common_name_de,
                 common_name_fr,
                 common_name_es,
                 'orders' AS entity_type
          FROM orders_fts
          WHERE orders_fts MATCH ?
          LIMIT $_referenceResultLimit
        ''',
        [wildcardTerm],
      ),
      (
        '''
          SELECT id,
                 name AS scientific_name,
                 NULL AS common_name_en,
                 NULL AS common_name_de,
                 NULL AS common_name_fr,
                 NULL AS common_name_es,
                 'classes' AS entity_type
          FROM classes_fts
          WHERE classes_fts MATCH ?
          LIMIT $_referenceResultLimit
        ''',
        [wildcardTerm],
      ),
    ];

    for (final (sql, args) in queries) {
      if (isAbandoned()) return results;
      try {
        results.addAll(await db.rawQuery(sql, args));
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
              '''
        SELECT s.id,
               g.name || ' ' || s.name AS scientific_name,
               s.common_name_en,
               s.common_name_de,
               s.common_name_fr,
               s.common_name_es,
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

    final db = await _referenceDatabase;
    final normalizedNames = scientificNames
        .map((name) => name.trim().toLowerCase())
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList();
    if (normalizedNames.isEmpty) return const [];

    final tableName = _referenceTableForEntityType(entityType);
    final hasCommonNames = entityType == 'families' || entityType == 'orders';
    const chunkSize = 100;

    try {
      final mergedById = <String, Map<String, dynamic>>{};

      for (var i = 0; i < normalizedNames.length; i += chunkSize) {
        final chunk = normalizedNames.skip(i).take(chunkSize).toList();
        final placeholders = List.filled(chunk.length, '?').join(', ');
        final rows = await db
            .rawQuery('''
        SELECT id,
               name AS scientific_name,
               ${hasCommonNames ? 'common_name_en,' : 'NULL AS common_name_en,'}
               ${hasCommonNames ? 'common_name_de,' : 'NULL AS common_name_de,'}
               ${hasCommonNames ? 'common_name_fr,' : 'NULL AS common_name_fr,'}
               ${hasCommonNames ? 'common_name_es,' : 'NULL AS common_name_es,'}
               '$entityType' AS entity_type
        FROM $tableName
        WHERE lower(trim(name)) IN ($placeholders)
        LIMIT $_referenceResultLimit
      ''', chunk)
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
                 s.common_name_en,
                 s.common_name_de,
                 s.common_name_fr,
                 s.common_name_es,
                 'species' AS entity_type
          FROM species s
          JOIN genera g ON g.id = s.genus
          WHERE s.status = 'active'
            AND (
              lower(g.name || ' ' || s.name) LIKE lower(?)
              OR lower(coalesce(s.common_name_en, '')) LIKE lower(?)
              OR lower(coalesce(s.common_name_de, '')) LIKE lower(?)
              OR lower(coalesce(s.common_name_fr, '')) LIKE lower(?)
              OR lower(coalesce(s.common_name_es, '')) LIKE lower(?)
            )
          LIMIT $_referenceResultLimit
        ''',
        [likeTerm, likeTerm, likeTerm, likeTerm, likeTerm],
      ),
      (
        '''
          SELECT id,
                 name AS scientific_name,
                 NULL AS common_name_en,
                 NULL AS common_name_de,
                 NULL AS common_name_fr,
                 NULL AS common_name_es,
                 'genera' AS entity_type
          FROM genera
          WHERE lower(name) LIKE lower(?)
          LIMIT $_referenceResultLimit
        ''',
        [likeTerm],
      ),
      (
        '''
          SELECT id,
                 name AS scientific_name,
                 common_name_en,
                 common_name_de,
                 common_name_fr,
                 common_name_es,
                 'families' AS entity_type
          FROM families
          WHERE lower(name) LIKE lower(?)
             OR lower(coalesce(common_name_en, '')) LIKE lower(?)
             OR lower(coalesce(common_name_de, '')) LIKE lower(?)
             OR lower(coalesce(common_name_fr, '')) LIKE lower(?)
             OR lower(coalesce(common_name_es, '')) LIKE lower(?)
          LIMIT $_referenceResultLimit
        ''',
        [likeTerm, likeTerm, likeTerm, likeTerm, likeTerm],
      ),
      (
        '''
          SELECT id,
                 name AS scientific_name,
                 common_name_en,
                 common_name_de,
                 common_name_fr,
                 common_name_es,
                 'orders' AS entity_type
          FROM orders
          WHERE lower(name) LIKE lower(?)
             OR lower(coalesce(common_name_en, '')) LIKE lower(?)
             OR lower(coalesce(common_name_de, '')) LIKE lower(?)
             OR lower(coalesce(common_name_fr, '')) LIKE lower(?)
             OR lower(coalesce(common_name_es, '')) LIKE lower(?)
          LIMIT $_referenceResultLimit
        ''',
        [likeTerm, likeTerm, likeTerm, likeTerm, likeTerm],
      ),
      (
        '''
          SELECT id,
                 name AS scientific_name,
                 NULL AS common_name_en,
                 NULL AS common_name_de,
                 NULL AS common_name_fr,
                 NULL AS common_name_es,
                 'classes' AS entity_type
          FROM classes
          WHERE lower(name) LIKE lower(?)
          LIMIT $_referenceResultLimit
        ''',
        [likeTerm],
      ),
    ];

    for (final (sql, args) in queries) {
      if (isAbandoned()) return results;
      try {
        results.addAll(await db.rawQuery(sql, args));
      } on DatabaseException {
        // continue with remaining tables
      }
    }

    return results;
  }

  Future<List<Map<String, dynamic>>> _searchDownloadedFts(
    String wildcardTerm,
  ) async {
    _logDebug('Search: querying downloaded names DB (FTS) "$wildcardTerm"');
    final stopwatch = Stopwatch()..start();
    final userDb = await _userDatabase;
    if (userDb == null) {
      _logDebug('Search: no user DB available, skipping downloaded FTS');
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
      FROM downloaded_name_search_documents d
      JOIN downloaded_name_search_fts f ON f.entity_key = d.entity_key
      WHERE downloaded_name_search_fts MATCH ?
      LIMIT $_downloadedResultLimit
    ''',
        [wildcardTerm],
      );
      _logDebug(
        'Search: downloaded FTS done "$wildcardTerm" '
        '(${rows.length} rows, ${stopwatch.elapsedMilliseconds}ms)',
      );
      return rows;
    } finally {
      stopwatch.stop();
    }
  }

  Future<List<Map<String, dynamic>>> _searchDownloadedFtsSafely(
    String wildcardTerm,
    bool Function() isAbandoned,
  ) async {
    return _runSerializedUserSearch(() async {
      try {
        return await _searchDownloadedFts(
          wildcardTerm,
        ).timeout(_userSearchTimeout, onTimeout: () => []);
      } on DatabaseException catch (e) {
        _logDebug('Search: downloaded FTS error: $e');
        return [];
      } on TimeoutException {
        _logDebug('Search: downloaded FTS timed out');
        return [];
      }
    }, isAbandoned: isAbandoned);
  }

  Future<List<Map<String, dynamic>>> _searchDownloadedFallbackIfNeeded({
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
      FROM ${DownloadedNameSearchRepository.documentsTable}
      WHERE normalized_search_text LIKE ? OR normalized_search_text LIKE ?
      LIMIT $_downloadedResultLimit
    ''',
        ['$normalizedTerm%', '%$normalizedTerm%'],
      );
      _logDebug(
        'Search: downloaded fallback done "$normalizedTerm" '
        '(${rows.length} rows, ${stopwatch.elapsedMilliseconds}ms)',
      );
      return rows;
    } finally {
      stopwatch.stop();
    }
  }

  Future<List<Map<String, dynamic>>> _searchDownloadedFallbackIfNeededSafely({
    required String normalizedTerm,
    required List<Map<String, dynamic>> existingRows,
    required bool Function() isAbandoned,
  }) async {
    return _runSerializedUserSearch(() async {
      try {
        return await _searchDownloadedFallbackIfNeeded(
          normalizedTerm: normalizedTerm,
          existingRows: existingRows,
        ).timeout(_userSearchTimeout, onTimeout: () => []);
      } on DatabaseException {
        return [];
      } on TimeoutException {
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
        .map(DownloadedNameSearchRepository.normalizeSearchText)
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
