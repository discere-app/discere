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
/// ## The list below is a ratchet, not an exemption list
///
/// Each entry records what that file measured when it was added. The test
/// fails in both directions: growing past the recorded number, and shrinking
/// well below it without lowering the number. The second half is what keeps
/// the list honest — a one-way list only ever accumulates and ends up
/// describing the past.
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
  'lib/app/about_page.dart': 300,
  'lib/app/bootstrap/bootstrap_app.dart': 431,
  'lib/app/diagnostics_page.dart': 782,
  'lib/app/main_screen_page.dart': 497,
  'lib/app/settings_page.dart': 273,
  'lib/app/sources_page.dart': 354,
  'lib/catalog/repository/inat_reference_resolver.dart': 318,
  'lib/catalog/repository/search_repository.dart': 489,
  'lib/catalog/repository/species_repository.dart': 798,
  'lib/catalog/repository/taxonomy_repository.dart': 900,
  'lib/catalog/search/search_species_delegate.dart': 646,
  'lib/catalog/search/search_worker.dart': 405,
  'lib/catalog/species_detail/species_detail_presenter.dart': 389,
  'lib/catalog/taxonomy_detail/species_filter_sheet.dart': 376,
  'lib/catalog/taxonomy_detail/taxonomy_detail_page.dart': 661,
  'lib/catalog/taxonomy_detail/taxonomy_species_selection_page.dart': 287,
  'lib/catalog/util/region_label_resolver.dart': 966,
  'lib/enrichment/pipeline/repository/enrichment_work_repository.dart': 1295,
  'lib/enrichment/pipeline/repository/runtime_common_name_repository.dart': 267,
  'lib/enrichment/pipeline/service/inat_photo_enrichment_service.dart': 345,
  'lib/enrichment/pipeline/service/inat_worker.dart': 317,
  'lib/enrichment/pipeline/service/taxonomy_common_name_enrichment_service.dart':
      392,
  'lib/enrichment/queue/repository/enrichment_job_repository.dart': 643,
  'lib/enrichment/queue/service/inat_enrichment_queue_service.dart': 989,
  'lib/external/inaturalist/inaturalist_service.dart': 829,
  'lib/learning/decks/create_deck_page.dart': 295,
  'lib/learning/decks/deck_card.dart': 399,
  'lib/learning/decks/deck_enrichment_hint.dart': 311,
  'lib/learning/decks/edit/deck_update_dialog.dart': 271,
  'lib/learning/decks/edit/edit_deck_page.dart': 600,
  'lib/learning/flashcard/deck_page.dart': 692,
  'lib/learning/flashcard/flashcard_front.dart': 274,
  'lib/learning/flashcard/flashcard_widget.dart': 284,
  'lib/learning/import/import_online_deck_list_tile.dart': 309,
  'lib/learning/import/import_online_decks_tab.dart': 311,
  'lib/learning/service/deck_import_service.dart': 278,
  'lib/learning/service/decks_service.dart': 270,
  'lib/learning/share/share_deck_page.dart': 490,
  'lib/shared/persistence/migration/migration_v12.dart': 403,
  'lib/shared/persistence/reference_database_provisioner.dart': 330,
  'lib/shared/service/host_cooldown_tracker.dart': 297,
  'lib/shared/service/image_service.dart': 267,
  'lib/shared/service/notification_service.dart': 272,
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
        if (entry.value > _budget && !_knownOversized.containsKey(entry.key))
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
          'as much as you added.\n'
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
