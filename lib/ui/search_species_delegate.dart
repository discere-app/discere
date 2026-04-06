import 'dart:async';

import 'package:discere/extensions/localization_extension.dart';
import 'package:discere/external/inaturalist/inaturalist_service.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:discere/ui/components/search_result_section_header.dart';
import 'package:discere/ui/components/species_search_result_card.dart';
import 'package:discere/ui/components/taxonomy_search_result_card.dart';
import 'package:discere/ui/pages/comming_soon_page.dart';
import 'package:discere/ui/pages/species_detail_page.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../model/language.dart';
import '../model/search/search_result.dart';
import '../persistence/search_repository.dart';
import '../service/common/language_service.dart';

class SearchSpeciesDelegate extends SearchDelegate<String> {
  static const Duration _searchDebounce = Duration(milliseconds: 450);
  static const int _minimumQueryLength = 2;
  static const bool _enableSearchDebugLogging = true;

  final SearchRepository _searchRepository;
  final LanguageService _languageService;
  final INaturalistService _iNatService;
  Timer? _searchDebounceTimer;
  Completer<List<SearchResult>>? _pendingSearchCompleter;
  String? _activeSearchQuery;
  Future<List<SearchResult>>? _activeSearchFuture;

  SearchSpeciesDelegate(
    this._searchRepository,
    this._languageService,
    this._iNatService,
  );

  @override
  List<Widget> buildActions(BuildContext context) {
    return [
      IconButton(
        icon: const Icon(Icons.clear),
        onPressed: () {
          query = ''; // Suchfeld leeren
        },
      ),
    ];
  }

  @override
  Widget buildResults(BuildContext context) {
    return _getResults(context);
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return query.isEmpty
        ? Center(child: Text(context.loc.speciesSearchStartSearch))
        : _getSuggestions(context);
  }

  @override
  void close(BuildContext context, String result) {
    _searchDebounceTimer?.cancel();
    _activeSearchQuery = null;
    _activeSearchFuture = null;
    super.close(context, result);
  }

  Widget _getResults(BuildContext context) {
    final futureResults = _getSearchFuture(query);
    _logDebug('Search UI: buildResults query="$query"');

    return FutureBuilder(
      future: futureResults,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        } else if (snapshot.hasError) {
          return Center(child: Text('${context.loc.error}: ${snapshot.error}'));
        } else {
          List<SearchResult> results = snapshot.data ?? [];
          if (results.isEmpty) {
            return Center(child: Text(context.loc.speciesSearchNoResult));
          }
          _logDebug('Search UI: rendering ${results.length} full results');
          return _buildGroupedResultsList(
            context,
            results,
            showThumbnails: true,
            showSectionHeaders: true,
          );
        }
      },
    );
  }

  Widget _getSuggestions(BuildContext context) {
    final futureSuggestions = _getSearchFuture(query);
    _logDebug('Search UI: buildSuggestions query="$query"');

    return FutureBuilder(
      future: futureSuggestions,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        } else if (snapshot.hasError) {
          return Center(child: Text('${context.loc.error}: ${snapshot.error}'));
        } else {
          List<SearchResult> suggestions = snapshot.data ?? [];
          if (suggestions.isEmpty) {
            return Center(child: Text(context.loc.speciesSearchNoResult));
          }
          _logDebug('Search UI: rendering ${suggestions.length} suggestions');
          return _buildGroupedResultsList(
            context,
            suggestions,
            showThumbnails: true,
            showSectionHeaders: true,
          );
        }
      },
    );
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () {
        close(context, ''); // Schließt die Suche
      },
    );
  }

  String _getPrimaryDisplayName(
    SearchResult searchResult,
    Language language,
    BuildContext context,
  ) {
    final localizedNames = _getLocalizedCommonNames(searchResult, language);
    if (localizedNames.isNotEmpty) return localizedNames.first;
    return searchResult.name.trim().isEmpty
        ? context.loc.commonUnknown
        : searchResult.name;
  }

  String? _getAdditionalNames(SearchResult searchResult, Language language) {
    final localizedNames = _getLocalizedCommonNames(searchResult, language);
    final additionalNames = localizedNames.skip(1).toList();
    if (additionalNames.isEmpty) return null;
    return additionalNames.join(', ');
  }

  List<String> _getLocalizedCommonNames(
    SearchResult searchResult,
    Language language,
  ) {
    final preferredNames = _splitCommonNames(
      searchResult.commonNames[language],
    );
    if (preferredNames.isNotEmpty) return preferredNames;

    if (language != Language.en) {
      final englishNames = _splitCommonNames(
        searchResult.commonNames[Language.en],
      );
      if (englishNames.isNotEmpty) return englishNames;
    }

    return const [];
  }

  List<String> _splitCommonNames(String? commonNames) {
    if (commonNames == null || commonNames.trim().isEmpty) {
      return const [];
    }

    final orderedNames = <String>[];
    final seenNames = <String>{};

    for (final rawName in commonNames.split(';')) {
      final trimmedName = rawName.trim();
      if (trimmedName.isEmpty) continue;

      final normalizedName = trimmedName
          .toLowerCase()
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (normalizedName.isEmpty || seenNames.contains(normalizedName)) {
        continue;
      }

      seenNames.add(normalizedName);
      orderedNames.add(trimmedName);
    }

    return orderedNames;
  }

  Future<List<SearchResult>> _getSearchFuture(String rawQuery) {
    final normalizedQuery = rawQuery.trim();
    if (normalizedQuery.length < _minimumQueryLength) {
      return _resetSearchState();
    }

    if (_activeSearchQuery == normalizedQuery && _activeSearchFuture != null) {
      _logDebug('Search UI: reusing active search for "$normalizedQuery"');
      return _activeSearchFuture!;
    }

    _cancelPendingSearch();

    final completer = Completer<List<SearchResult>>();
    _pendingSearchCompleter = completer;
    _activeSearchQuery = normalizedQuery;
    _activeSearchFuture = completer.future;

    _searchDebounceTimer = Timer(_searchDebounce, () async {
      try {
        _logDebug('Search UI: running search for "$normalizedQuery"');
        final results = await _searchRepository.searchAll(normalizedQuery);
        if (!completer.isCompleted) {
          completer.complete(results);
        }
      } catch (error, stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      } finally {
        final pendingCompleter = _pendingSearchCompleter;
        if (identical(pendingCompleter, completer)) {
          _pendingSearchCompleter = null;
        }
      }
    });

    return _activeSearchFuture!;
  }

  Future<List<SearchResult>> _resetSearchState() {
    _cancelPendingSearch();
    _activeSearchQuery = null;
    _activeSearchFuture = null;
    return Future.value(const <SearchResult>[]);
  }

  void _cancelPendingSearch() {
    _searchDebounceTimer?.cancel();
    final pendingCompleter = _pendingSearchCompleter;
    if (pendingCompleter != null && !pendingCompleter.isCompleted) {
      pendingCompleter.complete(const <SearchResult>[]);
    }
    _pendingSearchCompleter = null;
  }

  void _openSearchDetailView(BuildContext context, SearchResult selectedItem) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _evaluateDetailView(selectedItem),
      ),
    );
  }

  Widget _evaluateDetailView(SearchResult selectedItem) {
    switch (selectedItem.type) {
      case SearchEntityType.species:
        return SpeciesDetailPage(speciesId: selectedItem.id);

      default:
        return ComingSoonWidget(data: selectedItem);
    }
  }

  Widget _buildGroupedResultsList(
    BuildContext context,
    List<SearchResult> results, {
    required bool showThumbnails,
    required bool showSectionHeaders,
  }) {
    final groupedResults = _groupResultsByType(results);
    final selectedLanguage = _languageService.getLanguage();
    final shouldShowHeaders = showSectionHeaders && groupedResults.length > 1;
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

        return _buildResultCard(
          context,
          entry.result!,
          selectedLanguage,
          showThumbnails: showThumbnails,
        );
      },
    );
  }

  Widget _buildResultCard(
    BuildContext context,
    SearchResult result,
    Language selectedLanguage, {
    required bool showThumbnails,
  }) {
    final primaryName = _getPrimaryDisplayName(
      result,
      selectedLanguage,
      context,
    );
    final additionalNames = _getAdditionalNames(result, selectedLanguage);

    if (result.type == SearchEntityType.species) {
      return SpeciesSearchResultCard(
        primaryName: primaryName,
        scientificName: result.name.trim(),
        additionalNames: additionalNames,
        onTap: () => _openSearchDetailView(context, result),
        iNatService: _iNatService,
        showThumbnail: showThumbnails,
      );
    }

    return TaxonomySearchResultCard(
      primaryName: primaryName,
      scientificName: result.name.trim(),
      additionalNames: additionalNames,
      entityType: result.type,
      onTap: () => _openSearchDetailView(context, result),
    );
  }

  List<({SearchEntityType type, List<SearchResult> results})>
  _groupResultsByType(List<SearchResult> results) {
    final grouped = <SearchEntityType, List<SearchResult>>{};
    for (final result in results) {
      grouped.putIfAbsent(result.type, () => []).add(result);
    }

    const order = [
      SearchEntityType.species,
      SearchEntityType.genus,
      SearchEntityType.family,
      SearchEntityType.order,
      SearchEntityType.classType,
    ];

    return order
        .where(grouped.containsKey)
        .map((type) => (type: type, results: grouped[type]!))
        .toList();
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

  void _logDebug(String message) {
    if (_enableSearchDebugLogging && kDebugMode) {
      debugPrint(message);
    }
  }
}

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
