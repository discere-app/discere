import 'dart:async';

import 'package:discere/catalog/model/locale_place_mapping.dart';
import 'package:discere/catalog/model/search_result.dart';
import 'package:discere/catalog/model/taxon_rank.dart';
import 'package:discere/catalog/repository/common_name_repository.dart';
import 'package:discere/catalog/repository/inat_reference_resolver.dart';
import 'package:discere/catalog/repository/runtime_common_name_search_repository.dart';
import 'package:discere/catalog/repository/search_sql.dart';
import 'package:discere/catalog/search/search_worker.dart';
import 'package:discere/external/inaturalist/inaturalist_service.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/persistence/database_helper.dart';
import 'package:discere/shared/util/common_name_utils.dart';
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
  final SearchWorker _searchWorker;
  final INatReferenceResolver _inatResolver;
  final CommonNameRepository _commonNameRepository;
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
       _searchWorker = searchWorker,
       _inatResolver = INatReferenceResolver(
         referenceDatabase: () async =>
             database ?? await DatabaseHelper.referenceDb,
         iNatService: iNatService,
       ),
       _commonNameRepository = CommonNameRepository(
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

    final fallbackRows = await _inatResolver
        .resolveRuntimeTaxonomyReferenceRows(
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

    // One shared enrichment pass for every locally-known hit (regardless of
    // which branch found it), so search always shows the same merged,
    // priority-ordered common name the species detail page would — see
    // GitHub issue #111. `inatRows` go through the same merge as everything
    // else (they carry a resolved reference id whenever one was found), so a
    // hit that only surfaces through the online iNat fallback still agrees
    // with the detail page; the live iNat-reported preferred English name is
    // folded in afterwards by `_applyLiveINatPreferredNames`.
    final enrichedGroups = await _enrichRowGroupsWithMergedCommonNames([
      referenceRows,
      referenceFallbackRows,
      runtimeCommonNameRows,
      fallbackRows,
      inatRows,
    ]);
    if (isAbandoned()) return [];

    final workerResponse = await _searchWorker.process(
      SearchWorkerRequest(
        generation: myVersion,
        normalizedSearchTerm: normalizedTerm,
        referenceRows: enrichedGroups[0],
        downloadedRows: enrichedGroups[2],
        fallbackRows: enrichedGroups[3],
        inatRows: _applyLiveINatPreferredNames(enrichedGroups[4]),
        referenceFallbackRows: enrichedGroups[1],
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
      return await _enrichRowsWithReferenceCommonNamesOnly(db, rows);
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

    // A single UNION ALL across 9 FTS sub-queries (5 scientific-name tables +
    // 4 common-name lookups), so sqflite performs one DB round-trip instead
    // of 9. This prevents queue stacking when rapid typing launches multiple
    // concurrent searches on the same sqflite connection. Common-name
    // enrichment (reference + runtime, merged) happens once for all search
    // branches together in `searchAll`, not here.
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

    return rawById.values.toList();
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
    for (final sql in referenceLikeFallbackSqlStatements(
      _referenceResultLimit,
    )) {
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

    return rawById.values.toList();
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
          .rawQuery(runtimeCommonNameFtsSql(_runtimeCommonNameResultLimit), [
            wildcardTerm,
          ])
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
    return _userSearchRunner.run(
      () async {
        try {
          return await _searchRuntimeCommonNameFts(wildcardTerm);
        } on DatabaseException catch (e) {
          _logDebug('Search: runtime common-name FTS error: $e');
          return [];
        }
      },
      isAbandoned: isAbandoned,
      abandonedValue: const [],
    );
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
    return _userSearchRunner.run(
      () async {
        try {
          return await _searchRuntimeCommonNameFallbackIfNeeded(
            normalizedTerm: normalizedTerm,
            existingRows: existingRows,
          );
        } on DatabaseException {
          return [];
        }
      },
      isAbandoned: isAbandoned,
      abandonedValue: const [],
    );
  }

  /// Derives the reference-DB lookup id and the `runtime_common_names`
  /// lookup key for a raw search row, covering both row shapes `searchAll`
  /// produces:
  ///  - reference-FTS/LIKE-fallback rows: `id` is already the reference id,
  ///    there is no `entity_id` column.
  ///  - runtime-FTS rows (after `resolveRuntimeTaxonomyReferenceRows`):
  ///    species rows always carry `entity_id` = the real species id (set at
  ///    enrichment-write time); taxonomy rows carry `id` rewritten to a real
  ///    reference id when one was resolved, otherwise still their
  ///    search-document entity_key.
  ({String? referenceEntityId, String? runtimeEntityKey}) _resolveRowKeys(
    Map<String, dynamic> row,
  ) {
    final entityType = row['entity_type'] as String? ?? '';
    final scientificName = (row['scientific_name'] as String? ?? '').trim();

    if (entityType == 'species') {
      final speciesId = (row['entity_id'] as String?) ?? (row['id'] as String?);
      if (speciesId == null) {
        return (referenceEntityId: null, runtimeEntityKey: null);
      }
      return (
        referenceEntityId: speciesId,
        runtimeEntityKey: 'species:$speciesId',
      );
    }

    final rank = TaxonRank.fromEntityType(entityType);
    if (rank == null || scientificName.isEmpty) {
      return (referenceEntityId: null, runtimeEntityKey: null);
    }
    final runtimeEntityKey = rank.entityKey(scientificName);
    final rawId = row['id'] as String?;
    final referenceEntityId = (rawId != null && rawId != runtimeEntityKey)
        ? rawId
        : null;
    return (
      referenceEntityId: referenceEntityId,
      runtimeEntityKey: runtimeEntityKey,
    );
  }

  /// Bulk-fetches merged (runtime-wins) common names for every row across
  /// [rowGroups] in one pair of DB round trips (reference + runtime), then
  /// overwrites each row's `common_name_<lang>` columns with the merged,
  /// semicolon-joined result — the same shape `SearchWorker` already
  /// expects, so nothing downstream needs to change.
  Future<List<List<Map<String, dynamic>>>>
  _enrichRowGroupsWithMergedCommonNames(
    List<List<Map<String, dynamic>>> rowGroups,
  ) async {
    final flatRows = rowGroups.expand((group) => group).toList();
    if (flatRows.isEmpty) return rowGroups;

    final keysByRow = flatRows.map(_resolveRowKeys).toList(growable: false);
    final referenceIds = keysByRow
        .map((keys) => keys.referenceEntityId)
        .whereType<String>()
        .toSet();
    final runtimeKeys = keysByRow
        .map((keys) => keys.runtimeEntityKey)
        .whereType<String>()
        .toSet();

    final referenceDb = await _referenceDatabase;
    final userDb = await _userDatabase;
    final referenceNames = await _commonNameRepository.loadReferenceCommonNames(
      referenceDb,
      referenceIds,
    );
    final runtimeNames = userDb == null
        ? const <String, Map<Language, List<String>>>{}
        : await _commonNameRepository.loadRuntimeCommonNames(
            userDb,
            runtimeKeys,
          );

    final enrichedRows = <Map<String, dynamic>>[
      for (var i = 0; i < flatRows.length; i++)
        _applyMergedCommonNames(
          flatRows[i],
          referenceNames[keysByRow[i].referenceEntityId],
          runtimeNames[keysByRow[i].runtimeEntityKey],
        ),
    ];

    var cursor = 0;
    return [
      for (final group in rowGroups)
        enrichedRows.sublist(cursor, cursor += group.length),
    ];
  }

  /// Reference-only variant used by `searchQuick`, which intentionally
  /// skips user-DB lookups to stay fast on every keystroke (see its
  /// docstring). Still routes through the shared [CommonNameRepository] so
  /// it can't drift from the reference-ordering rule the full search and
  /// the detail page use.
  Future<List<Map<String, dynamic>>> _enrichRowsWithReferenceCommonNamesOnly(
    Database db,
    List<Map<String, dynamic>> rows,
  ) async {
    if (rows.isEmpty) return rows;
    final referenceIds = rows.map((row) => row['id'] as String).toSet();
    final referenceNames = await _commonNameRepository.loadReferenceCommonNames(
      db,
      referenceIds,
    );
    return [
      for (final row in rows)
        _applyMergedCommonNames(row, referenceNames[row['id'] as String], null),
    ];
  }

  Map<String, dynamic> _applyMergedCommonNames(
    Map<String, dynamic> row,
    Map<Language, List<String>>? referenceNames,
    Map<Language, List<String>>? runtimeNames,
  ) {
    if (referenceNames == null && runtimeNames == null) return row;
    final merged = _commonNameRepository.merge(
      referenceNames ?? const {},
      runtimeNames ?? const {},
    );
    return {
      ...row,
      'common_name_en': _joinNames(merged[Language.en]),
      'common_name_de': _joinNames(merged[Language.de]),
      'common_name_fr': _joinNames(merged[Language.fr]),
      'common_name_es': _joinNames(merged[Language.es]),
    };
  }

  String? _joinNames(List<String>? names) =>
      (names == null || names.isEmpty) ? null : names.join(';');

  /// Appends each row's live iNat-reported preferred English name (attached
  /// by [INatReferenceResolver] under
  /// [INatReferenceResolver.inatPreferredCommonNameEnKey]) to its already
  /// reference/runtime-merged English name list — an EN fallback for a
  /// species with no locally cached English name at all, same as the
  /// detail page would eventually cache once this species gets enriched.
  /// Appended, not prepended: an already-merged local name (particularly a
  /// runtime one) is what the detail page shows too, and must keep winning
  /// so search stays in agreement with it — see GitHub issue #111.
  List<Map<String, dynamic>> _applyLiveINatPreferredNames(
    List<Map<String, dynamic>> rows,
  ) {
    return [
      for (final row in rows)
        if (row[INatReferenceResolver.inatPreferredCommonNameEnKey] != null)
          _withLiveINatPreferredName(row)
        else
          row,
    ];
  }

  Map<String, dynamic> _withLiveINatPreferredName(Map<String, dynamic> row) {
    final livePreferred =
        row[INatReferenceResolver.inatPreferredCommonNameEnKey] as String;
    final mergedEn = deduplicateCommonNames([
      ...splitCommonNames(row['common_name_en'] as String?),
      livePreferred,
    ]);
    final result = Map<String, dynamic>.from(row)
      ..remove(INatReferenceResolver.inatPreferredCommonNameEnKey)
      ..['common_name_en'] = mergedEn.join(';');
    return result;
  }

  void _logDebug(String message) {
    if (_enableSearchDebugLogging) {
      _log.debug(message);
    }
  }
}
