import 'dart:async';

import 'package:discere/catalog/comparison/model/comparison_list.dart';
import 'package:discere/catalog/comparison/model/removed_comparison_species.dart';
import 'package:discere/catalog/comparison/repository/comparison_list_repository.dart';
import 'package:discere/shared/util/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

/// The user's comparison lists, held in memory so the overview, the add sheet
/// and an open comparison all read the same state synchronously and rebuild
/// on every change.
///
/// Every change is one statement or one transaction of the repository, so
/// none of them needs `UserDataWrites`: a restart closing the database waits
/// for a running transaction or rolls it back, never leaving half of it.
class ComparisonListService extends ChangeNotifier {
  static final _log = Logger.forType(ComparisonListService);

  final ComparisonListRepository _repository;

  List<ComparisonList>? _lists;
  Object? _loadError;

  ComparisonListService(this._repository) {
    unawaited(_refresh());
  }

  /// Newest first, or null until the first load has finished.
  List<ComparisonList>? get lists => _lists;

  /// Why the lists could not be loaded, while [lists] is still null.
  Object? get loadError => _loadError;

  /// The list [id], or null when there is none (any more) or the lists have
  /// not loaded yet.
  ComparisonList? listById(String id) =>
      _lists?.where((list) => list.id == id).firstOrNull;

  /// Creates a list named [name] holding [speciesIds], and answers its id.
  Future<String> createList(String name, Set<String> speciesIds) async {
    final id = const Uuid().v4();
    await _repository.createList(
      id: id,
      name: name,
      speciesIds: speciesIds,
      at: DateTime.now(),
    );
    await _refresh();
    return id;
  }

  /// Adds [speciesIds] to [listId]; a species already in it is kept once.
  Future<void> addSpecies(String listId, Set<String> speciesIds) async {
    await _repository.addSpecies(listId, speciesIds);
    await _refresh();
  }

  /// Removes [speciesId] from [listId], and answers what [restoreSpecies]
  /// takes to undo it (null when the list did not hold it). A list left
  /// empty stays.
  Future<RemovedComparisonSpecies?> removeSpecies(
    String listId,
    String speciesId,
  ) async {
    final removed = await _repository.removeSpecies(listId, speciesId);
    await _refresh();
    return removed;
  }

  /// Puts [removed] back where it was in its list.
  Future<void> restoreSpecies(RemovedComparisonSpecies removed) async {
    await _repository.restoreSpecies(removed);
    await _refresh();
  }

  Future<void> renameList(String listId, String name) async {
    await _repository.renameList(listId, name);
    await _refresh();
  }

  Future<void> deleteList(String listId) async {
    await _repository.deleteList(listId);
    await _refresh();
  }

  Future<void> _refresh() async {
    try {
      _lists = await _repository.getLists();
      _loadError = null;
    } catch (error, stackTrace) {
      _log.warn(
        'Comparison lists load failed',
        error: error,
        stackTrace: stackTrace,
      );
      _loadError = error;
    }
    notifyListeners();
  }
}
