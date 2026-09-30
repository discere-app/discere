import 'package:discere/catalog/model/search_result.dart';
import 'package:discere/catalog/search/search_result_list_item.dart';
import 'package:discere/catalog/search/search_result_section_header.dart';
import 'package:discere/catalog/search/search_results_presenter.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// The search results, grouped by rank and labelled per group.
///
/// Groups and their rows share one flat entry list rather than a list per
/// group, so the whole screen stays a single scrollable [ListView.builder]
/// that only builds the rows in view — a search can answer with hundreds of
/// hits across five ranks.
///
/// The headers only appear once there is more than one group: with a single
/// rank on screen the label repeats what every row already says.
class SearchResultsGroupedList extends StatelessWidget {
  static const _resultsPresenter = SearchResultsPresenter();

  final List<SearchResult> results;
  final Language selectedLanguage;
  final Future<String?> Function(String scientificName) resolveThumbnailUrl;
  final void Function(SearchResult result) onResultTap;

  const SearchResultsGroupedList({
    super.key,
    required this.results,
    required this.selectedLanguage,
    required this.resolveThumbnailUrl,
    required this.onResultTap,
  });

  @override
  Widget build(BuildContext context) {
    final groupedResults = _resultsPresenter.groupByType(results);
    final shouldShowHeaders = groupedResults.length > 1;
    final entries = <_SearchListEntry>[];

    for (final group in groupedResults) {
      if (shouldShowHeaders) {
        entries.add(
          _SearchListEntry.header(
            title: _pluralLabelForEntityType(context, group.type),
            count: group.results.length,
          ),
        );
      }

      for (final item in group.results) {
        entries.add(_SearchListEntry.result(item));
      }
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenPadding,
        AppSpacing.s4,
        AppSpacing.screenPadding,
        AppSpacing.s24,
      ),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        if (entry.headerTitle != null) {
          return SearchResultSectionHeader(
            title: entry.headerTitle!,
            count: entry.headerCount!,
          );
        }

        return SearchResultListItem(
          result: entry.result!,
          selectedLanguage: selectedLanguage,
          resolveThumbnailUrl: resolveThumbnailUrl,
          onTap: () => onResultTap(entry.result!),
        );
      },
    );
  }

  String _pluralLabelForEntityType(
    BuildContext context,
    SearchEntityType entityType,
  ) {
    switch (entityType) {
      case SearchEntityType.species:
        return context.loc.speciesSearchSpeciesSection;
      case SearchEntityType.genus:
        return context.loc.speciesSearchGeneraSection;
      case SearchEntityType.family:
        return context.loc.speciesSearchFamiliesSection;
      case SearchEntityType.order:
        return context.loc.speciesSearchOrdersSection;
      case SearchEntityType.classType:
        return context.loc.speciesSearchClassesSection;
    }
  }
}

/// One line of the flat list: either a group header or a result, never both.
class _SearchListEntry {
  final SearchResult? result;
  final String? headerTitle;
  final int? headerCount;

  const _SearchListEntry._({this.result, this.headerTitle, this.headerCount});

  factory _SearchListEntry.result(SearchResult result) {
    return _SearchListEntry._(result: result);
  }

  factory _SearchListEntry.header({required String title, required int count}) {
    return _SearchListEntry._(headerTitle: title, headerCount: count);
  }
}
