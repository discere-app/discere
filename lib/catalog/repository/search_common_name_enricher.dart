import 'package:discere/catalog/model/taxon_rank.dart';
import 'package:discere/catalog/repository/common_name_repository.dart';
import 'package:discere/catalog/repository/inat_reference_resolver.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/util/common_name_utils.dart';
import 'package:sqflite/sqflite.dart';

/// Fills in the common names a search row should show.
///
/// A raw search row carries whatever names its source happened to have. What
/// the user should see is the merge of the curated reference names and the
/// place-aware runtime ones — and for iNaturalist rows, the name iNaturalist
/// itself prefers.
///
/// Separate from the queries that produced the rows: this is post-processing
/// over results, not a lookup, and it works the same whichever query the rows
/// came from.
class SearchCommonNameEnricher {
  final CommonNameRepository _commonNameRepository;
  final Future<Database> Function() _referenceDatabase;
  final Future<Database?> Function() _userDatabase;

  const SearchCommonNameEnricher(
    this._commonNameRepository, {
    required Future<Database> Function() referenceDatabase,
    required Future<Database?> Function() userDatabase,
  }) : _referenceDatabase = referenceDatabase,
       _userDatabase = userDatabase;

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
  enrichRowGroups(
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

    final referenceDb = await _referenceDatabase();
    final userDb = await _userDatabase();
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
  Future<List<Map<String, dynamic>>> enrichWithReferenceNamesOnly(
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
  List<Map<String, dynamic>> applyLiveINatPreferredNames(
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
}
