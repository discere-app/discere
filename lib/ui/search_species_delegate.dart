import 'package:discere/extensions/localization_extension.dart';
import 'package:discere/ui/pages/comming_soon_page.dart';
import 'package:discere/ui/pages/species_detail_page.dart';
import 'package:flutter/material.dart';

import '../model/language.dart';
import '../model/search/search_result.dart';
import '../persistence/search_repository.dart';
import '../service/common/language_service.dart';

class SearchSpeciesDelegate extends SearchDelegate<String> {
  final SearchRepository _searchRepository;
  final LanguageService _languageService;

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

  Widget _getResults(BuildContext context) {
    Future<List<SearchResult>> futureResults =
        _searchRepository.searchAll(query);

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
              return ListTile(
                title: Text(_getCommonName(
                    item, _languageService.getLanguage(), context)),
                subtitle: Text(
                    item.commonNames[_languageService.getLanguage()] ?? ''),
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
    Future<List<SearchResult>> futureSuggestions =
        _searchRepository.searchAll(query);

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
              return ListTile(
                title: Text(_getCommonName(
                    suggestion, _languageService.getLanguage(), context)),
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

  String _getCommonName(
      SearchResult searchResult, Language language, BuildContext context) {
    final commonName = searchResult.commonNames[language] ??
        searchResult.commonNames[Language.en];

    if (commonName == null || commonName.toString().trim().isEmpty) {
      return context.loc.commonUnknown;
    }
    return commonName.toString();
  }

  void _openSearchDetailView(BuildContext context, SearchResult selectedItem) {
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (context) => _evaluateDetailView(selectedItem)));
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
