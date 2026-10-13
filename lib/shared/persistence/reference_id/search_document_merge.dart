import 'package:discere/shared/persistence/reference_id/keyed_id_rewrite.dart';
import 'package:sqflite/sqflite.dart';

const searchDocumentsTable = 'runtime_common_name_search_documents';
const _searchFtsTable = 'runtime_common_name_search_fts';

const _nameColumns = [
  'common_name_en',
  'common_name_de',
  'common_name_fr',
  'common_name_es',
];

/// The columns [mergeSearchDocuments] reads.
const searchDocumentValueColumns = [..._nameColumns, 'normalized_search_text'];

/// Rebuilds one search document from the documents of the entities that
/// became one, so the merged entity stays findable under every name either
/// was found under.
///
/// A document is a snapshot of an entity's names, one `;`-separated list per
/// language. The merged document keeps the surviving document's lists and
/// appends the names only the others had; its search text joins all of
/// theirs. The scientific name stays the survivor's — the one of the entity
/// that kept its ID, when there is one.
CollisionOutcome mergeSearchDocuments(List<IdRow> group) {
  final survivor = existingRowOrSmallestOldId(group);
  final ordered = [survivor, ...group.where((row) => row != survivor)];
  final update = <String, Object?>{};
  for (final column in _nameColumns) {
    final merged = _union(
      ordered.map((row) => row.values[column] as String?),
      separator: ';',
    );
    if (merged != survivor.values[column]) update[column] = merged;
  }
  // Whole texts, not words: a search matches phrases inside one text.
  final searchText = {
    for (final row in ordered)
      if (row.values['normalized_search_text'] case final String text
          when text.isNotEmpty)
        text,
  }.join(' ');
  if (searchText != survivor.values['normalized_search_text']) {
    update['normalized_search_text'] = searchText;
  }
  return CollisionOutcome(survivor, update);
}

/// Keeps the full-text index in step with the documents: it has no trigger,
/// and its rows share the documents' rowids. A removed document's row goes;
/// a merged one's is written again from the document.
Future<void> syncSearchIndex(
  Transaction txn, {
  required List<int> droppedRowIds,
  required List<int> mergedRowIds,
}) async {
  for (final rowId in [...droppedRowIds, ...mergedRowIds]) {
    await txn.delete(_searchFtsTable, where: 'rowid = ?', whereArgs: [rowId]);
  }
  final columns = ['scientific_name', ..._nameColumns].join(', ');
  for (final rowId in mergedRowIds) {
    await txn.rawInsert(
      'INSERT INTO $_searchFtsTable (rowid, $columns) '
      'SELECT rowid, $columns FROM $searchDocumentsTable WHERE rowid = ?',
      [rowId],
    );
  }
}

/// The distinct non-empty parts of [values] split at [separator], in order
/// of first appearance, joined again — or null when there are none.
String? _union(Iterable<String?> values, {required String separator}) {
  final parts = <String>{};
  for (final value in values) {
    if (value == null) continue;
    parts.addAll(
      value.split(separator).map((part) => part.trim()).where(
        (part) => part.isNotEmpty,
      ),
    );
  }
  return parts.isEmpty ? null : parts.join(separator);
}
