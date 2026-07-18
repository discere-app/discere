import 'package:discere/catalog/model/search_result.dart';
import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/catalog/service/watchlist_service.dart';
import 'package:discere/catalog/species_detail/species_detail_content.dart';
import 'package:discere/catalog/taxonomy_detail/taxonomy_detail_page.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/service/language_service.dart';
import 'package:discere/shared/ui/app_bottom_navigation_bar.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class SpeciesDetailPage extends StatelessWidget {
  final SpeciesWithLocalImages species;
  final List<String> deckNames;
  final bool isRefreshingImages;
  final Language? language;
  final Widget Function(String speciesId)? buildSpeciesDetailPage;

  const SpeciesDetailPage({
    super.key,
    required this.species,
    this.deckNames = const [],
    this.isRefreshingImages = false,
    this.language,
    this.buildSpeciesDetailPage,
  });

  void _navigateToTaxon(BuildContext context, SearchResult result) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TaxonomyDetailPage(
          searchResult: result,
          buildSpeciesDetailPage: buildSpeciesDetailPage,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(species.species.getBinomialName()),
        actions: [
          Consumer<WatchlistService>(
            builder: (context, watchlistService, child) {
              final isWatchlisted = watchlistService.containsSpecies(
                species.species.id,
              );
              return IconButton(
                key: const Key('species_detail_watchlist_button'),
                tooltip: isWatchlisted
                    ? context.loc.watchListRemove
                    : context.loc.watchListAdd,
                icon: Icon(
                  isWatchlisted ? Icons.bookmark : Icons.bookmark_border,
                ),
                onPressed: () {
                  watchlistService.toggleSpecies(species.species.id);
                },
              );
            },
          ),
        ],
      ),
      bottomNavigationBar: const AppBottomNavigationBar(),
      body: SafeArea(
        child: Consumer<LanguageService>(
          builder: (context, languageService, child) {
            final currentLanguage = language ?? languageService.getLanguage();
            return SpeciesDetailContent(
              species: species,
              language: currentLanguage,
              deckNames: deckNames,
              isRefreshingImages: isRefreshingImages,
              onNavigateToTaxon: buildSpeciesDetailPage != null
                  ? (result) => _navigateToTaxon(context, result)
                  : null,
            );
          },
        ),
      ),
    );
  }
}
