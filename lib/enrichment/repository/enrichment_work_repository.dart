import 'dart:convert';

import 'package:discere/enrichment/model/enrichment_work_plan.dart';
import 'package:discere/enrichment/repository/enrichment_job_repository.dart';
import 'package:discere/shared/persistence/database_helper.dart';
import 'package:sqflite/sqflite.dart';

class OwnedTaxonomyWorkItem {
  final String workKey;
  final String runtimeEntityKey;
  final String rank;
  final String scientificName;
  final Set<String> speciesIds;

  const OwnedTaxonomyWorkItem({
    required this.workKey,
    required this.runtimeEntityKey,
    required this.rank,
    required this.scientificName,
    required this.speciesIds,
  });
}

class EnrichmentWorkRepository {
  static const speciesWorkTable = 'enrichment_species_work';
  static const taxonomyWorkTable = 'enrichment_taxonomy_work';

  final Database? _injectedDb;

  const EnrichmentWorkRepository([this._injectedDb]);

  Future<Database> get _db async => _injectedDb ?? DatabaseHelper.userDb;

  Future<Map<String, List<String>>> assignSpeciesOwners({
    required Map<String, Set<String>> speciesIdsByDeckId,
    required List<String> prioritizedDeckIds,
  }) async {
    final db = await _db;
    return db.transaction((txn) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final existingRows = await txn.query(speciesWorkTable);
      final existingBySpeciesId = {
        for (final row in existingRows) row['species_id'] as String: row,
      };
      final assignments = <String, List<String>>{
        for (final deckId in prioritizedDeckIds) deckId: <String>[],
      };
      final deckPriority = <String, int>{
        for (var index = 0; index < prioritizedDeckIds.length; index++)
          prioritizedDeckIds[index]: index,
      };

      final allSpeciesIds =
          speciesIdsByDeckId.values
              .expand((speciesIds) => speciesIds)
              .toSet()
              .toList(growable: false)
            ..sort((left, right) {
              final leftFrequency = speciesIdsByDeckId.values
                  .where((speciesIds) => speciesIds.contains(left))
                  .length;
              final rightFrequency = speciesIdsByDeckId.values
                  .where((speciesIds) => speciesIds.contains(right))
                  .length;
              final frequencyComparison = rightFrequency.compareTo(
                leftFrequency,
              );
              if (frequencyComparison != 0) {
                return frequencyComparison;
              }
              return left.compareTo(right);
            });

      for (final speciesId in allSpeciesIds) {
        final deckIds = prioritizedDeckIds
            .where(
              (deckId) =>
                  speciesIdsByDeckId[deckId]?.contains(speciesId) ?? false,
            )
            .toList(growable: false);
        if (deckIds.isEmpty) {
          continue;
        }
        final existingRow = existingBySpeciesId[speciesId];
        final existingOwnerDeckId = existingRow?['owner_deck_id'] as String?;
        final ownerDeckId = deckIds.contains(existingOwnerDeckId)
            ? existingOwnerDeckId!
            : deckIds.first;
        assignments.putIfAbsent(ownerDeckId, () => <String>[]).add(speciesId);
        await txn.insert(speciesWorkTable, {
          'species_id': speciesId,
          'owner_deck_id': ownerDeckId,
          'deck_ids_json': jsonEncode(deckIds),
          'deck_count': deckIds.length,
          'base_state': existingRow?['base_state'] ?? 'pending',
          'inat_primary_state': existingRow?['inat_primary_state'] ?? 'pending',
          'species_common_names_state':
              existingRow?['species_common_names_state'] ?? 'pending',
          'inat_backfill_state':
              existingRow?['inat_backfill_state'] ?? 'pending',
          'updated_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      // Drop stale rows for species that are no longer part of the active plan.
      final activeSpeciesIds = allSpeciesIds.toSet();
      for (final row in existingRows) {
        final speciesId = row['species_id'] as String;
        if (activeSpeciesIds.contains(speciesId)) {
          continue;
        }
        final deckIds = _decodeStringList(row['deck_ids_json']);
        final hasTrackedDeck = deckIds.any(deckPriority.containsKey);
        if (!hasTrackedDeck) {
          continue;
        }
        await txn.delete(
          speciesWorkTable,
          where: 'species_id = ?',
          whereArgs: [speciesId],
        );
      }

      return assignments.map(
        (deckId, speciesIds) =>
            MapEntry(deckId, List<String>.unmodifiable(speciesIds)),
      );
    });
  }

  Future<List<OwnedTaxonomyWorkItem>> assignTaxonomyOwners({
    required String deckId,
    required Iterable<TaxonomyWorkPlanItem> items,
  }) async {
    final db = await _db;
    return db.transaction((txn) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final rows = await txn.query(taxonomyWorkTable);
      final existingByRuntimeEntityKey = {
        for (final row in rows) row['runtime_entity_key'] as String: row,
      };
      final ownedItems = <OwnedTaxonomyWorkItem>[];

      for (final item in items) {
        final existingRow = existingByRuntimeEntityKey[item.runtimeEntityKey];
        final ownerDeckId = existingRow?['owner_deck_id'] as String? ?? deckId;
        final deckIds = {
          ..._decodeStringList(existingRow?['deck_ids_json']),
          deckId,
        }.toList(growable: false)..sort();
        final speciesIds = {
          ..._decodeStringList(existingRow?['species_ids_json']),
          ...item.speciesIds,
        }.toList(growable: false)..sort();
        final workKey = existingRow?['work_key'] as String? ?? item.workKey;
        await txn.insert(taxonomyWorkTable, {
          'work_key': workKey,
          'runtime_entity_key': item.runtimeEntityKey,
          'owner_deck_id': ownerDeckId,
          'deck_ids_json': jsonEncode(deckIds),
          'species_ids_json': jsonEncode(speciesIds),
          'rank': item.rank,
          'scientific_name': item.scientificName,
          'common_names_state': existingRow?['common_names_state'] ?? 'pending',
          'updated_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        if (ownerDeckId == deckId) {
          ownedItems.add(
            OwnedTaxonomyWorkItem(
              workKey: workKey,
              runtimeEntityKey: item.runtimeEntityKey,
              rank: item.rank,
              scientificName: item.scientificName,
              speciesIds: item.speciesIds,
            ),
          );
        }
      }

      return List<OwnedTaxonomyWorkItem>.unmodifiable(ownedItems);
    });
  }

  /// Species that already reached `succeeded` for [stage], regardless of which
  /// deck owns them. Used by the executor to skip work that another deck has
  /// already completed for overlapping species.
  Future<Set<String>> loadSucceededSpeciesIdsForStage(
    EnrichmentStage stage,
  ) async {
    final column = _speciesStateColumnForStage(stage);
    if (column == null) return const <String>{};
    final db = await _db;
    final rows = await db.query(
      speciesWorkTable,
      columns: const ['species_id'],
      where: '$column = ?',
      whereArgs: const ['succeeded'],
    );
    return {for (final row in rows) row['species_id'] as String};
  }

  Future<void> markSpeciesStageCompleted({
    required EnrichmentStage stage,
    required Iterable<String> speciesIds,
  }) async {
    final normalizedSpeciesIds = _normalizedValues(speciesIds);
    if (normalizedSpeciesIds.isEmpty) return;
    final db = await _db;
    final columnName = _speciesStateColumnForStage(stage);
    if (columnName == null) {
      return;
    }
    await db.update(
      speciesWorkTable,
      {
        columnName: 'succeeded',
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where:
          'species_id IN (${List.filled(normalizedSpeciesIds.length, '?').join(', ')})',
      whereArgs: normalizedSpeciesIds,
    );
  }

  Future<void> markTaxonomyCommonNamesCompleted(
    Iterable<String> workKeys,
  ) async {
    final normalizedWorkKeys = _normalizedValues(workKeys);
    if (normalizedWorkKeys.isEmpty) return;
    final db = await _db;
    await db.update(
      taxonomyWorkTable,
      {
        'common_names_state': 'succeeded',
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where:
          'work_key IN (${List.filled(normalizedWorkKeys.length, '?').join(', ')})',
      whereArgs: normalizedWorkKeys,
    );
  }

  Future<void> releaseDeck(String deckId) async {
    final normalizedDeckId = deckId.trim();
    if (normalizedDeckId.isEmpty) return;
    final db = await _db;
    await db.transaction((txn) async {
      final speciesRows = await txn.query(speciesWorkTable);
      for (final row in speciesRows) {
        final deckIds = _decodeStringList(row['deck_ids_json'])
          ..removeWhere((value) => value == normalizedDeckId);
        final ownerDeckId = row['owner_deck_id'] as String?;
        if (deckIds.isEmpty || ownerDeckId == normalizedDeckId) {
          await txn.delete(
            speciesWorkTable,
            where: 'species_id = ?',
            whereArgs: [row['species_id']],
          );
          continue;
        }
        await txn.update(
          speciesWorkTable,
          {
            'deck_ids_json': jsonEncode(deckIds),
            'deck_count': deckIds.length,
            'updated_at': DateTime.now().millisecondsSinceEpoch,
          },
          where: 'species_id = ?',
          whereArgs: [row['species_id']],
        );
      }

      final taxonomyRows = await txn.query(taxonomyWorkTable);
      for (final row in taxonomyRows) {
        final deckIds = _decodeStringList(row['deck_ids_json'])
          ..removeWhere((value) => value == normalizedDeckId);
        final ownerDeckId = row['owner_deck_id'] as String?;
        if (deckIds.isEmpty || ownerDeckId == normalizedDeckId) {
          await txn.delete(
            taxonomyWorkTable,
            where: 'work_key = ?',
            whereArgs: [row['work_key']],
          );
          continue;
        }
        await txn.update(
          taxonomyWorkTable,
          {
            'deck_ids_json': jsonEncode(deckIds),
            'updated_at': DateTime.now().millisecondsSinceEpoch,
          },
          where: 'work_key = ?',
          whereArgs: [row['work_key']],
        );
      }
    });
  }

  static String? _speciesStateColumnForStage(EnrichmentStage stage) {
    switch (stage) {
      case EnrichmentStage.base:
        return 'base_state';
      case EnrichmentStage.inatPrimary:
        return 'inat_primary_state';
      case EnrichmentStage.names:
        return 'species_common_names_state';
      case EnrichmentStage.inatBackfill:
        return 'inat_backfill_state';
      case EnrichmentStage.nameResolution:
      case EnrichmentStage.cover:
        return null;
    }
  }

  static List<String> _normalizedValues(Iterable<String> values) {
    final normalized = <String>[];
    final seen = <String>{};
    for (final value in values) {
      final trimmed = value.trim();
      if (trimmed.isEmpty || !seen.add(trimmed)) {
        continue;
      }
      normalized.add(trimmed);
    }
    return normalized;
  }

  static List<String> _decodeStringList(Object? rawValue) {
    if (rawValue is! String || rawValue.isEmpty) {
      return <String>[];
    }
    final decoded = jsonDecode(rawValue);
    if (decoded is! List) {
      return <String>[];
    }
    return decoded
        .whereType<String>()
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
  }
}
