/// Architecture test (ARCH-07) — file-size budget for `lib/`.
///
/// The budget answers "how big may a *new* file be", not "what do we tolerate
/// today". The repo's own habit is a median of 62 code lines and a 75th
/// percentile of 174, so 250 is roughly four times typical — generous enough
/// that nothing well-factored trips it, tight enough that a file crossing it
/// is genuinely worth a second look.
///
/// **Comments and blank lines do not count.** They are only 8% of the tree
/// and the oversized files are not oversized because of them (the two worst
/// page files carry 0% comments), so counting them would change almost
/// nothing in the ranking — but it would put a file just under the limit in
/// the position of having to choose between an explanation and the rule.
/// Documenting non-obvious decisions is this codebase's strongest habit and
/// the budget must not tax it.
///
/// A line counts as a comment when it *starts* with `//`, which is exact
/// here: `lib/` contains no block comments, and a trailing comment after code
/// sits on a line that already counts.
///
/// ## Two lists, because there are two answers
///
/// Over budget means "look at this", not "this is wrong". A file can be long
/// because it was never factored, and it can be long because the thing it
/// describes is long. Those need different lists, or the second kind teaches
/// everyone that entries are allowed to sit there forever — and then the
/// first kind sits there too.
///
/// [_knownOversized] is the debt: a ratchet. Each entry records what that
/// file measured when it was added, and the test fails in both directions —
/// growing past the recorded number, and shrinking well below it without
/// lowering the number. The second half is what keeps the list honest; a
/// one-way list only ever accumulates and ends up describing the past.
///
/// [_permanentlyOversized] is not debt. Each entry carries the reason its
/// length is not evidence of bad factoring. It records no size, deliberately:
/// a ceiling would make it a second ratchet, and the two lists would blur
/// back into one. The reason is the guard instead — a file that outgrows its
/// own justification has a reason that stopped being true, and noticing that
/// is a review judgment no scan can make.
///
/// Run with: flutter test test/architecture/file_size_budget_test.dart
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'arch_assertions.dart';

/// Code lines a new file may have.
const _budget = 250;

/// How far a listed file may shrink before its ceiling has to be lowered.
/// Without slack every deleted handful of lines would fail the build; with
/// too much, a file could halve and still hold its old allowance.
const _slack = 25;

/// Files already over budget when it was introduced, with the size each had
/// at that point. Lower a number when the file shrinks; delete the entry once
/// the file is under budget. Do not add entries — a new file over budget
/// means the file wants splitting.
const _knownOversized = <String, int>{
  'lib/app/info/about_page.dart': 300,
  'lib/app/bootstrap/bootstrap_app.dart': 431,
  'lib/catalog/repository/search_repository.dart': 487,
  'lib/catalog/repository/species_repository.dart': 798,
  'lib/catalog/repository/taxonomy_repository.dart': 900,
  'lib/catalog/search/search_species_delegate.dart': 646,
  'lib/catalog/search/search_worker.dart': 405,
  'lib/catalog/species_detail/species_detail_presenter.dart': 389,
  'lib/catalog/taxonomy_detail/species_filter_sheet.dart': 376,
  'lib/catalog/util/region_label_resolver.dart': 966,
  'lib/enrichment/pipeline/repository/enrichment_work_repository.dart': 1295,
  'lib/enrichment/pipeline/service/taxonomy_common_name_enrichment_service.dart':
      392,
  'lib/enrichment/queue/repository/enrichment_job_repository.dart': 442,
  'lib/enrichment/queue/service/inat_enrichment_queue_service.dart': 606,
  'lib/external/inaturalist/inaturalist_service.dart': 829,
  'lib/learning/decks/deck_card.dart': 399,
  'lib/learning/decks/deck_enrichment_hint.dart': 312,
  'lib/learning/decks/edit/edit_deck_page.dart': 600,
  'lib/learning/flashcard/deck_page.dart': 693,
  'lib/learning/flashcard/flashcard_front.dart': 274,
  'lib/learning/import/import_online_deck_list_tile.dart': 309,
  'lib/learning/import/import_online_decks_tab.dart': 311,
  'lib/learning/service/deck_import_service.dart': 278,
  'lib/shared/persistence/reference_database_provisioner.dart': 330,
  'lib/shared/service/host_cooldown_tracker.dart': 297,
  'lib/shared/service/notification_service.dart': 272,
};

/// Files whose length is not a factoring problem, each with the reason why.
///
/// Unlike [_knownOversized] these are not expected to shrink, so they record
/// no size — see the library doc. Adding one is a claim that has to survive
/// review: "it would be awkward to split" is not a reason, "splitting it
/// would duplicate the core it shares" is.
const _permanentlyOversized = <String, String>{
  'lib/shared/persistence/migration/migration_v12.dart':
      'A migration is a snapshot of a schema at one point in time. It may '
          'neither be split (a migration runs as one step) nor be kept in '
          'sync with current code (it has to keep describing the schema as '
          'it was). The only migration over budget.',
  'lib/enrichment/pipeline/service/inat_worker.dart':
      'One handler per enrichment capability behind one dispatch. The length '
          'is the number of capabilities, and they share a single rate-limit '
          'budget whose spacing only works while one object owns it — five '
          'files that nothing but the dispatcher calls would move the code '
          'without reducing what has to be read together.',
  'lib/enrichment/pipeline/service/inat_photo_enrichment_service.dart':
      'The primary and backfill paths are two entry points over one '
          'fetch-and-persist core. Splitting them means either duplicating '
          'that core or introducing a base class to share it.',
  'lib/catalog/repository/inat_reference_resolver.dart':
      'One resolution path — iNaturalist result to reference row — with a '
          'branch per rank. The private methods are its steps, not separate '
          'responsibilities.',
  'lib/learning/service/decks_service.dart':
      'A CRUD surface over decks. The length is the number of deck '
          'operations the app has, each one short; there is no second '
          'responsibility to lift out.',
  'lib/shared/service/image_service.dart':
      'Deck covers and batched species images are two entry-point families '
          'over one download-save-resolve core, which a split would '
          'duplicate.',
  'lib/enrichment/pipeline/repository/runtime_common_name_repository.dart':
      'One table family, plus the shape of the search document it writes '
          'into it. Marginally over budget and cohesive.',
  'lib/learning/decks/create_deck_page.dart':
      'A single page whose bulk is async orchestration against '
          'BuildContext/setState/mounted, which by convention stays in the '
          'State class rather than moving into a presenter.',
  'lib/learning/decks/edit/deck_update_dialog.dart':
      'A dialog with its two sections already in their own widget classes. '
          'Marginally over budget.',
  'lib/learning/flashcard/flashcard_widget.dart':
      'A flip-card gesture and animation state machine. Drag handling, '
          'settle animation and face rendering read the same few fields; '
          'splitting them means passing that state across a boundary.',
  'lib/catalog/taxonomy_detail/taxonomy_species_selection_page.dart':
      'A selection page with its selection state. Nothing self-contained '
          'enough to lift out.',
};

int _codeLines(File file) {
  var count = 0;
  for (final line in file.readAsLinesSync()) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('//')) continue;
    count++;
  }
  return count;
}

/// Generated output and the migration-free `l10n` tree are not authored here,
/// so their size says nothing about how the code is factored.
bool _isGenerated(String path) =>
    path.endsWith('.g.dart') || path.startsWith('lib/l10n/');

void main() {
  final sizes = <String, int>{};
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final path = entity.path.replaceAll('\\', '/');
    if (_isGenerated(path)) continue;
    sizes[path] = _codeLines(entity);
  }

  test('the scan sees the source tree', () {
    expectScanFound(sizes.length, 200, 'Dart files under lib/');
    expectScanFound(
      sizes.values.fold(0, (sum, lines) => sum + lines),
      20000,
      'code lines',
    );
  });

  test('no new file exceeds the budget', () {
    final violations = [
      for (final entry in sizes.entries)
        if (entry.value > _budget &&
            !_knownOversized.containsKey(entry.key) &&
            !_permanentlyOversized.containsKey(entry.key))
          '${entry.key}: ${entry.value} code lines',
    ]..sort();

    expect(
      violations,
      isEmpty,
      reason:
          'ARCH-07: these files are over the $_budget-line budget and are not '
          'on the ratchet list.\n'
          'Split them — a page whose private widgets have grown into sections '
          'gives each its own file; a repository that has grown a second '
          'responsibility gives it its own class. Adding an entry to '
          '_knownOversized is not the fix: that list only shrinks.\n'
          'Violations:\n  ${violations.join('\n  ')}',
    );
  });

  test('no listed file grew past its recorded size', () {
    final violations = [
      for (final entry in _knownOversized.entries)
        if ((sizes[entry.key] ?? 0) > entry.value)
          '${entry.key}: ${sizes[entry.key]} code lines, '
              'recorded ${entry.value}',
    ]..sort();

    expect(
      violations,
      isEmpty,
      reason:
          'ARCH-07: these files are already over budget and got bigger.\n'
          'Take the addition somewhere else, or shrink the file by at least '
          'as much as you added. If the growth is genuinely warranted — an '
          'import that replaces a worse dependency, say — raise the recorded '
          'number in the same commit, so the growth is a line in the diff '
          'someone can object to rather than something that just happened.\n'
          'Violations:\n  ${violations.join('\n  ')}',
    );
  });

  test('every permanent exemption still applies', () {
    final violations = <String>[];
    for (final entry in _permanentlyOversized.entries) {
      final actual = sizes[entry.key];
      if (actual == null) {
        violations.add('${entry.key}: no longer exists — remove the entry');
      } else if (actual <= _budget) {
        violations.add(
          '${entry.key}: down to $actual lines, under budget — the exemption '
          'is no longer doing anything, remove it',
        );
      }
      if (entry.value.trim().length < 40) {
        violations.add(
          '${entry.key}: the reason is too short to be one — say why this '
          'file\'s length is not a factoring problem',
        );
      }
    }
    for (final path in _knownOversized.keys) {
      if (_permanentlyOversized.containsKey(path)) {
        violations.add(
          '$path: on both lists — a file is either debt or exempt, not both',
        );
      }
    }
    violations.sort();

    expect(
      violations,
      isEmpty,
      reason:
          'ARCH-07: the permanent-exemption list no longer matches the tree. '
          'An exemption that outlived its file, or its reason, is how this '
          'list turns into the blanket allowance it exists to avoid.\n'
          'Violations:\n  ${violations.join('\n  ')}',
    );
  });

  test('the ratchet list is still accurate', () {
    final violations = <String>[];
    for (final entry in _knownOversized.entries) {
      final actual = sizes[entry.key];
      if (actual == null) {
        violations.add('${entry.key}: no longer exists — remove the entry');
      } else if (actual <= _budget) {
        violations.add(
          '${entry.key}: down to $actual lines, under budget — remove the '
          'entry',
        );
      } else if (actual < entry.value - _slack) {
        violations.add(
          '${entry.key}: down to $actual lines from ${entry.value} — lower '
          'the recorded size to $actual',
        );
      }
    }
    violations.sort();

    expect(
      violations,
      isEmpty,
      reason:
          'ARCH-07: the ratchet list no longer matches the tree. This is the '
          'half that keeps it a ratchet rather than a permanent exemption '
          'list: a recorded size that is never lowered lets a file regrow '
          'into an allowance it no longer needs.\n'
          'Violations:\n  ${violations.join('\n  ')}',
    );
  });
}
