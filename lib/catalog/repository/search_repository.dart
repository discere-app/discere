import 'dart:async';

import 'package:discere/catalog/model/locale_place_mapping.dart';
import 'package:discere/catalog/model/search_result.dart';
import 'package:discere/catalog/repository/inat_reference_resolver.dart';
import 'package:discere/catalog/repository/locale_aware_common_name_sql.dart';
import 'package:discere/catalog/repository/runtime_common_name_search_repository.dart';
import 'package:discere/catalog/repository/search_sql.dart';
import 'package:discere/catalog/search/search_worker.dart';
import 'package:discere/external/inaturalist/inaturalist_service.dart';
import 'package:discere/shared/persistence/database_helper.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:discere/shared/util/serialized_task_runner.dart';
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
  final LocalePlaceMapping? _localeMapping;
  final SearchWorker _searchWorker;
  final INatReferenceResolver _inatResolver;
  final SerializedTaskRunner _referenceSearchRunner = SerializedTaskRunner();
  final SerializedTaskRunner _userSearchRunner = SerializedTaskRunner();
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
    required SearchWorker searchWorker,
  }) : _injectedReferenceDb = database,
       _injectedUserDb = userDatabase,
       _localeMapping = localeMapping,
       _searchWorker = searchWorker,
       _inatResolver = INatReferenceResolver(
         referenceDatabase: () async =>
             database ?? await DatabaseHelper.referenceDb,
         iNatService: iNatService,
         localeMapping: localeMapping,
       );

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
    final runtimeCommonNameRows = await _inatResolver
        .resolveRuntimeTaxonomyReferenceRows(localResults[1]);
    final referenceFallbackRows = await _searchReferenceFallbackIfNeeded(
      rawTerm: trimmedTerm,
      existingRows: [...referenceRows, ...runtimeCommonNameRows],
      isAbandoned: isAbandoned,
    );
    if (isAbandoned()) return [];

    final inatRows = referenceRows.isEmpty && runtimeCommonNameRows.isEmpty
        ? await _inatResolver.searchAndResolveINat(trimmedTerm)
        : const <Map<String, dynamic>>[];
    if (isAbandoned()) return [];

    _logDebug(
      'Search: reference FTS=${referenceRows.length}, '
      'runtime common-name FTS=${runtimeCommonNameRows.length}, '
      'iNat=${inatRows.length}, '
      'reference LIKE=${referenceFallbackRows.length}',
    );

    final fallbackRows = await _inatResolver.resolveRuntimeTaxonomyReferenceRows(
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

    return _referenceSearchRunner.run(
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
        referenceSpeciesFtsSql(_referenceResultLimit),
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
    final inatRows = await _inatResolver.searchAndResolveINat(trimmedTerm);
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
    final phase1Sql = referenceFtsUnionAllSql(_referenceResultLimit);

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

  Future<List<Map<String, dynamic>>> _searchReferenceFallbackIfNeeded({
    required String rawTerm,
    required List<Map<String, dynamic>> existingRows,
    required bool Function() isAbandoned,
  }) async {
    if (rawTerm.trim().isEmpty || existingRows.isNotEmpty) return const [];

    final db = await _referenceDatabase;
    final likeTerm = '%${rawTerm.trim()}%';
    final results = <Map<String, dynamic>>[];

    final rawById = <String, Map<String, dynamic>>{};
    for (final sql in referenceLikeFallbackSqlStatements(_referenceResultLimit)) {
      final args = [likeTerm, likeTerm];
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
            runtimeCommonNameFtsSql(_runtimeCommonNameResultLimit),
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
    return _userSearchRunner.run(() async {
      try {
        return await _searchRuntimeCommonNameFts(wildcardTerm);
      } on DatabaseException catch (e) {
        _logDebug('Search: runtime common-name FTS error: $e');
        return [];
      }
    }, isAbandoned: isAbandoned, abandonedValue: const []);
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
        runtimeCommonNameFallbackSql(
          RuntimeCommonNameSearchRepository.documentsTable,
          _runtimeCommonNameResultLimit,
        ),
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
    return _userSearchRunner.run(() async {
      try {
        return await _searchRuntimeCommonNameFallbackIfNeeded(
          normalizedTerm: normalizedTerm,
          existingRows: existingRows,
        );
      } on DatabaseException {
        return [];
      }
    }, isAbandoned: isAbandoned, abandonedValue: const []);
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
