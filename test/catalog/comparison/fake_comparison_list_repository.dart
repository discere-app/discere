import 'package:discere/catalog/comparison/model/comparison_list.dart';
import 'package:discere/catalog/comparison/model/removed_comparison_species.dart';
import 'package:discere/catalog/comparison/repository/comparison_list_repository.dart';

/// Comparison lists in memory, for widget tests, which cannot await a real
/// database inside the fake-async zone. Keeps the repository's rules that the
/// widgets rely on: newest list first, species in the order added, each once.
class FakeComparisonListRepository implements ComparisonListRepository {
  final List<ComparisonList> _lists;

  FakeComparisonListRepository([List<ComparisonList> lists = const []])
    : _lists = List.of(lists);

  @override
  Future<List<ComparisonList>> getLists() async => List.unmodifiable(_lists);

  @override
  Future<void> createList({
    required String id,
    required String name,
    required Set<String> speciesIds,
    required DateTime at,
  }) async {
    _lists.insert(
      0,
      ComparisonList(id: id, name: name, speciesIds: speciesIds.toList()),
    );
  }

  @override
  Future<void> addSpecies(String listId, Set<String> speciesIds) async =>
      _update(
        listId,
        (list) => _with(
          list,
          speciesIds: [
            ...list.speciesIds,
            ...speciesIds.where((id) => !list.speciesIds.contains(id)),
          ],
        ),
      );

  /// The position it answers is the species' index, which [restoreSpecies]
  /// inserts it at again.
  @override
  Future<RemovedComparisonSpecies?> removeSpecies(
    String listId,
    String speciesId,
  ) async {
    final index = _lists
        .firstWhere((list) => list.id == listId)
        .speciesIds
        .indexOf(speciesId);
    if (index < 0) return null;
    _update(
      listId,
      (list) => _with(
        list,
        speciesIds: [
          for (final id in list.speciesIds)
            if (id != speciesId) id,
        ],
      ),
    );
    return RemovedComparisonSpecies(
      listId: listId,
      speciesId: speciesId,
      position: index,
    );
  }

  @override
  Future<void> restoreSpecies(RemovedComparisonSpecies removed) async {
    if (!_lists.any((list) => list.id == removed.listId)) return;
    _update(removed.listId, (list) {
      if (list.speciesIds.contains(removed.speciesId)) return list;
      final ids = List.of(list.speciesIds);
      ids.insert(removed.position.clamp(0, ids.length), removed.speciesId);
      return _with(list, speciesIds: ids);
    });
  }

  @override
  Future<void> renameList(String listId, String name) async =>
      _update(listId, (list) => _with(list, name: name));

  @override
  Future<void> deleteList(String listId) async =>
      _lists.removeWhere((list) => list.id == listId);

  void _update(String listId, ComparisonList Function(ComparisonList) change) {
    final index = _lists.indexWhere((list) => list.id == listId);
    _lists[index] = change(_lists[index]);
  }

  ComparisonList _with(
    ComparisonList list, {
    String? name,
    List<String>? speciesIds,
  }) => ComparisonList(
    id: list.id,
    name: name ?? list.name,
    speciesIds: speciesIds ?? list.speciesIds,
  );
}
