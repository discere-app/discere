import 'package:discere/catalog/search/search_species_delegate.dart';
import 'package:discere/catalog/service/species_search_service.dart';
import 'package:discere/external/inaturalist/inaturalist_service.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/service/language_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The app bar with the species search and the settings entry point.
///
/// Assembles the search delegate here rather than in the page: it needs four
/// collaborators that only matter for searching, and none of them has
/// anything to do with the rest of the screen.
class MainScreenAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget Function(String speciesId, [Language? language])
  buildSpeciesDetailPage;
  final Future<bool> Function(
    BuildContext context,
    Set<String> speciesIds,
    Set<String> speciesNames,
  )
  onAddToDeck;
  final VoidCallback onOpenSettings;

  const MainScreenAppBar({
    required this.buildSpeciesDetailPage,
    required this.onAddToDeck,
    required this.onOpenSettings,
    super.key,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  void _openSearch(BuildContext context) {
    final searchService = Provider.of<SpeciesSearchService>(
      context,
      listen: false,
    );
    showSearch(
      context: context,
      delegate: SearchSpeciesDelegate(
        searchService,
        Provider.of<LanguageService>(context, listen: false),
        searchService.searchOnline,
        Provider.of<INaturalistService>(context, listen: false)
            .fetchThumbnailUrl,
        buildSpeciesDetailPage,
        onAddToDeck,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Text(context.loc.appTitle),
      actions: [
        IconButton(
          icon: const Icon(Icons.search),
          onPressed: () => _openSearch(context),
        ),
        IconButton(
          onPressed: onOpenSettings,
          icon: const Icon(Icons.settings),
        ),
      ],
    );
  }
}
