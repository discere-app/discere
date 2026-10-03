import 'package:discere/catalog/common/taxon_identity/display_language_selector.dart';
import 'package:discere/catalog/common/taxon_identity/display_languages.dart';
import 'package:discere/catalog/model/search_result.dart';
import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/catalog/service/watchlist_service.dart';
import 'package:discere/catalog/species_detail/species_detail_content.dart';
import 'package:discere/catalog/taxonomy_detail/taxonomy_detail_page.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/service/language_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class SpeciesDetailPage extends StatefulWidget {
  final SpeciesWithLocalImages species;
  final List<String> deckNames;
  final bool isRefreshingImages;

  /// The language the page starts in when it should not simply follow the
  /// app language — a deck's language, when opened from that deck.
  final Language? language;
  final Widget Function(String speciesId)? buildSpeciesDetailPage;
  final Future<bool> Function(
    BuildContext context,
    Set<String> speciesIds,
    Set<String> speciesNames,
  )?
  onAddToDeck;
  final GlobalKey? addToDeckButtonKey;

  const SpeciesDetailPage({
    super.key,
    required this.species,
    this.deckNames = const [],
    this.isRefreshingImages = false,
    this.language,
    this.buildSpeciesDetailPage,
    this.onAddToDeck,
    this.addToDeckButtonKey,
  });

  @override
  State<SpeciesDetailPage> createState() => _SpeciesDetailPageState();
}

class _SpeciesDetailPageState extends State<SpeciesDetailPage> {
  /// The language picked in the header's selector for this page's names, or
  /// null while nothing has been picked — the names then follow
  /// [SpeciesDetailPage.language] or the app language like the rest of the
  /// page, including a change to either. A peek for this one page: it is
  /// neither stored nor handed to the pages opened from here.
  Language? _nameLanguageOverride;

  void _navigateToTaxon(SearchResult result) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TaxonomyDetailPage(
          searchResult: result,
          buildSpeciesDetailPage: widget.buildSpeciesDetailPage,
          onAddToDeck: widget.onAddToDeck,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.species.species.getBinomialName()),
        actions: [
          if (widget.onAddToDeck != null)
            IconButton(
              key:
                  widget.addToDeckButtonKey ??
                  const Key('species_detail_add_to_deck_button'),
              tooltip: context.loc.speciesDetailAddToDeckTooltip,
              icon: const Icon(Icons.playlist_add),
              onPressed: () => widget.onAddToDeck!(
                context,
                {widget.species.species.id},
                {widget.species.species.getBinomialName()},
              ),
            ),
          Consumer<WatchlistService>(
            builder: (context, watchlistService, child) {
              final isWatchlisted = watchlistService.containsSpecies(
                widget.species.species.id,
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
                  watchlistService.toggleSpecies(widget.species.species.id);
                },
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Consumer<LanguageService>(
          builder: (context, languageService, child) {
            final pageLanguage =
                widget.language ?? languageService.getLanguage();
            final nameLanguage = _nameLanguageOverride ?? pageLanguage;
            return SpeciesDetailContent(
              species: widget.species,
              nameLanguage: nameLanguage,
              languageSelector: DisplayLanguageSelector(
                language: nameLanguage,
                selectableLanguages: selectableDisplayLanguages(
                  widget.species.species.commonNames,
                  nameLanguage,
                ),
                onSelected: (language) =>
                    setState(() => _nameLanguageOverride = language),
              ),
              summaryLanguage: pageLanguage,
              deckNames: widget.deckNames,
              isRefreshingImages: widget.isRefreshingImages,
              onNavigateToTaxon: widget.buildSpeciesDetailPage != null
                  ? _navigateToTaxon
                  : null,
            );
          },
        ),
      ),
    );
  }
}
