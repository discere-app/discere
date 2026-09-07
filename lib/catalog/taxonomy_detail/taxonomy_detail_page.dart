import 'package:discere/catalog/common/species_list_item/species_list_item_presenter.dart';
import 'package:discere/catalog/model/search_result.dart';
import 'package:discere/catalog/model/taxonomy_detail.dart';
import 'package:discere/catalog/repository/taxonomy_repository.dart';
import 'package:discere/catalog/taxonomy_detail/taxonomy_detail_presenter.dart';
import 'package:discere/catalog/taxonomy_detail/taxonomy_species_selection_page.dart';
import 'package:discere/catalog/taxonomy_detail/widgets/taxonomy_detail_content.dart';
import 'package:discere/shared/extensions/app_exception_localization.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/service/language_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class TaxonomyDetailPage extends StatefulWidget {
  final SearchResult searchResult;
  final Widget Function(String speciesId)? buildSpeciesDetailPage;
  final Future<bool> Function(
    BuildContext context,
    Set<String> speciesIds,
    Set<String> speciesNames,
  )?
  onAddToDeck;

  const TaxonomyDetailPage({
    super.key,
    required this.searchResult,
    this.buildSpeciesDetailPage,
    this.onAddToDeck,
  });

  @override
  State<TaxonomyDetailPage> createState() => _TaxonomyDetailPageState();
}

class _TaxonomyDetailPageState extends State<TaxonomyDetailPage> {
  static const _speciesListItemPresenter = SpeciesListItemPresenter();
  late final TaxonomyRepository _repository;
  final TaxonomyDetailPresenter _presenter = const TaxonomyDetailPresenter();
  late Future<TaxonomyDetail> _futureDetail;
  late Future<List<SearchResult>> _futureChildren;

  @override
  void initState() {
    super.initState();
    _repository = context.read<TaxonomyRepository>();
    _futureDetail = _repository.getDetail(widget.searchResult);
    _futureChildren = _repository.getChildren(widget.searchResult);
  }

  void _navigateTo(SearchResult result) {
    if (result.type == SearchEntityType.species) {
      final buildPage = widget.buildSpeciesDetailPage;
      if (buildPage == null) return;
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => buildPage(result.id)));
    } else {
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
  }

  void _openSpeciesSelection() {
    final onAddToDeck = widget.onAddToDeck;
    if (onAddToDeck == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TaxonomySpeciesSelectionPage(
          taxon: widget.searchResult,
          onAddToDeck: onAddToDeck,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _presenter.pageTitleFor(widget.searchResult.type, context.loc),
        ),
        actions: [
          if (widget.onAddToDeck != null)
            IconButton(
              key: const Key('taxonomy_detail_add_to_deck_button'),
              tooltip: context.loc.taxonomyDetailAddSpeciesToDeckTooltip,
              icon: const Icon(Icons.playlist_add),
              onPressed: _openSpeciesSelection,
            ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<TaxonomyDetail>(
          future: _futureDetail,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Text(
                  '${context.loc.error}: ${context.loc.describeError(snapshot.error)}',
                ),
              );
            }
            if (!snapshot.hasData) {
              return Center(child: Text(context.loc.commonNoData));
            }

            return Consumer<LanguageService>(
              builder: (context, languageService, _) {
                final viewData = _presenter.present(
                  snapshot.data!,
                  languageService.getLanguage(),
                  context.loc,
                );
                return TaxonomyDetailContent(
                  viewData: viewData,
                  type: snapshot.data!.result.type,
                  childrenFuture: _futureChildren,
                  language: languageService.getLanguage(),
                  speciesListItemPresenter: _speciesListItemPresenter,
                  onNavigate: _navigateTo,
                  canNavigateToSpecies: widget.buildSpeciesDetailPage != null,
                );
              },
            );
          },
        ),
      ),
    );
  }
}
