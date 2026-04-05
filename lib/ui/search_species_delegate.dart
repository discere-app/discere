import 'dart:async';

import 'package:discere/extensions/localization_extension.dart';
import 'package:discere/ui/pages/comming_soon_page.dart';
import 'package:discere/ui/pages/species_detail_page.dart';
import 'package:flutter/material.dart';

import '../model/language.dart';
import '../model/search/search_result.dart';
import '../persistence/search_repository.dart';
import '../service/common/language_service.dart';

class SearchSpeciesDelegate extends SearchDelegate<String> {
  static const Duration _searchDebounce = Duration(milliseconds: 300);
  static const int _minimumQueryLength = 2;

  final SearchRepository _searchRepository;
  final LanguageService _languageService;
  String? _lastSearchQuery;
  Future<List<SearchResult>>? _lastSearchFuture;
  Timer? _searchDebounceTimer;
  Completer<List<SearchResult>>? _pendingSearchCompleter;

  SearchSpeciesDelegate(this._searchRepository, this._languageService);

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
    super.close(context, result);
  }

  Widget _getResults(BuildContext context) {
    final futureResults = _getSearchFuture(query);

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
          return ListView.builder(
            itemCount: results.length,
            itemBuilder: (context, index) {
              final item = results[index];
              final selectedLanguage = _languageService.getLanguage();
              return ListTile(
                title: Text(
                  _getPrimaryDisplayName(item, selectedLanguage, context),
                ),
                subtitle: _buildSecondaryText(item, selectedLanguage),
                trailing: _buildEntityTypeChip(context, item.type),
                onTap: () {
                  _openSearchDetailView(context, item);
                },
              );
            },
          );
        }
      },
    );
  }

  Widget _getSuggestions(BuildContext context) {
    final futureSuggestions = _getSearchFuture(query);

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
          return ListView.builder(
            itemCount: suggestions.length,
            itemBuilder: (context, index) {
              final suggestion = suggestions[index];
              final selectedLanguage = _languageService.getLanguage();
              return ListTile(
                title: Text(
                  _getPrimaryDisplayName(suggestion, selectedLanguage, context),
                ),
                subtitle: _buildSecondaryText(suggestion, selectedLanguage),
                trailing: _buildEntityTypeChip(context, suggestion.type),
                onTap: () {
                  _openSearchDetailView(context, suggestion);
                },
              );
            },
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

  Widget? _buildSecondaryText(SearchResult searchResult, Language language) {
    final scientificName = searchResult.name.trim();
    final localizedNames = _getLocalizedCommonNames(searchResult, language);
    final additionalNames = localizedNames.skip(1).toList();
    final subtitleParts = <String>[];

    if (scientificName.isNotEmpty) {
      subtitleParts.add(scientificName);
    }
    if (additionalNames.isNotEmpty) {
      subtitleParts.add(additionalNames.join(', '));
    }

    if (subtitleParts.isEmpty) return null;
    return Text(subtitleParts.join(' • '));
  }

  Widget _buildEntityTypeChip(
    BuildContext context,
    SearchEntityType entityType,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final icon = _iconForEntityType(entityType);
    final label = _labelForEntityType(context, entityType);
    final chipColors = _colorsForEntityType(colorScheme, entityType);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: chipColors.$1,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: chipColors.$2),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: chipColors.$2,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconForEntityType(SearchEntityType entityType) {
    switch (entityType) {
      case SearchEntityType.species:
        return Icons.pets;
      case SearchEntityType.genus:
        return Icons.account_tree_outlined;
      case SearchEntityType.family:
        return Icons.category_outlined;
      case SearchEntityType.order:
        return Icons.schema_outlined;
      case SearchEntityType.classType:
        return Icons.layers_outlined;
    }
  }

  String _labelForEntityType(
    BuildContext context,
    SearchEntityType entityType,
  ) {
    switch (entityType) {
      case SearchEntityType.species:
        return context.loc.speciesDetailTitle;
      case SearchEntityType.genus:
        return context.loc.classificationGenus;
      case SearchEntityType.family:
        return context.loc.classificationFamily;
      case SearchEntityType.order:
        return context.loc.classificationOrder;
      case SearchEntityType.classType:
        return context.loc.classificationClass;
    }
  }

  (Color, Color) _colorsForEntityType(
    ColorScheme colorScheme,
    SearchEntityType entityType,
  ) {
    switch (entityType) {
      case SearchEntityType.species:
        return (
          colorScheme.tertiaryContainer.withValues(alpha: 0.55),
          colorScheme.onTertiaryContainer,
        );
      case SearchEntityType.genus:
        return (
          colorScheme.primaryContainer.withValues(alpha: 0.55),
          colorScheme.onPrimaryContainer,
        );
      case SearchEntityType.family:
        return (
          colorScheme.secondaryContainer.withValues(alpha: 0.55),
          colorScheme.onSecondaryContainer,
        );
      case SearchEntityType.order:
        return (
          colorScheme.surfaceContainerHighest,
          colorScheme.onSurfaceVariant,
        );
      case SearchEntityType.classType:
        return (colorScheme.surfaceContainerHigh, colorScheme.onSurfaceVariant);
    }
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
      _searchDebounceTimer?.cancel();
      if (_pendingSearchCompleter != null &&
          !_pendingSearchCompleter!.isCompleted) {
        _pendingSearchCompleter!.complete(const []);
      }
      _pendingSearchCompleter = null;
      _lastSearchQuery = normalizedQuery;
      _lastSearchFuture = Future.value(const []);
      return _lastSearchFuture!;
    }

    if (_lastSearchFuture != null && _lastSearchQuery == normalizedQuery) {
      return _lastSearchFuture!;
    }

    _lastSearchQuery = normalizedQuery;
    _searchDebounceTimer?.cancel();
    if (_pendingSearchCompleter != null &&
        !_pendingSearchCompleter!.isCompleted) {
      _pendingSearchCompleter!.complete(const []);
    }

    final completer = Completer<List<SearchResult>>();
    _pendingSearchCompleter = completer;
    _lastSearchFuture = completer.future;

    _searchDebounceTimer = Timer(_searchDebounce, () async {
      try {
        final results = await _searchRepository.searchAll(normalizedQuery);
        if (!completer.isCompleted) {
          completer.complete(results);
        }
      } catch (error, stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      } finally {
        if (identical(_pendingSearchCompleter, completer)) {
          _pendingSearchCompleter = null;
        }
      }
    });

    return _lastSearchFuture!;
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
}
