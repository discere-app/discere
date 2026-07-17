import 'package:discere/catalog/common/species_list_item/species_list_item.dart';
import 'package:discere/catalog/common/species_list_item/species_list_item_presenter.dart';
import 'package:discere/catalog/model/search_result.dart';
import 'package:discere/catalog/model/taxonomy_detail.dart';
import 'package:discere/catalog/repository/taxonomy_repository.dart';
import 'package:discere/catalog/search/search_result_card.dart';
import 'package:discere/catalog/search/search_result_thumbnail.dart';
import 'package:discere/catalog/search/taxonomy_search_result_card.dart';
import 'package:discere/catalog/taxonomy_detail/search_taxonomy_style.dart';
import 'package:discere/catalog/taxonomy_detail/taxonomy_classification_row_view_model.dart';
import 'package:discere/catalog/taxonomy_detail/taxonomy_detail_presenter.dart';
import 'package:discere/catalog/taxonomy_detail/taxonomy_detail_view_model.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/external/inaturalist_service.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/service/language_service.dart';
import 'package:discere/shared/ui/app_bottom_navigation_bar.dart';
import 'package:discere/shared/ui/copyable_text.dart';
import 'package:discere/shared/ui/detail_content_widgets.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class TaxonomyDetailPage extends StatefulWidget {
  final SearchResult searchResult;
  final Widget Function(String speciesId)? buildSpeciesDetailPage;

  const TaxonomyDetailPage({
    super.key,
    required this.searchResult,
    this.buildSpeciesDetailPage,
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
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => buildPage(result.id)),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TaxonomyDetailPage(
            searchResult: result,
            buildSpeciesDetailPage: widget.buildSpeciesDetailPage,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _presenter.pageTitleFor(widget.searchResult.type, context.loc),
        ),
      ),
      bottomNavigationBar: const AppBottomNavigationBar(),
      body: SafeArea(
        child: FutureBuilder<TaxonomyDetail>(
          future: _futureDetail,
          builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text('${context.loc.error}: ${snapshot.error}'),
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
              return _TaxonomyDetailContent(
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

class _TaxonomyDetailContent extends StatelessWidget {
  final TaxonomyDetailViewModel viewData;
  final SearchEntityType type;
  final Future<List<SearchResult>> childrenFuture;
  final Language language;
  final SpeciesListItemPresenter speciesListItemPresenter;
  final void Function(SearchResult) onNavigate;
  final bool canNavigateToSpecies;

  const _TaxonomyDetailContent({
    required this.viewData,
    required this.type,
    required this.childrenFuture,
    required this.language,
    required this.speciesListItemPresenter,
    required this.onNavigate,
    required this.canNavigateToSpecies,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = SearchTaxonomyStyle.colorFor(type);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s16,
        AppSpacing.s20,
        AppSpacing.s16,
        AppSpacing.s24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.s20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  accent.withValues(alpha: 0.16),
                  theme.colorScheme.surfaceContainerLow,
                ],
              ),
              border: Border.all(color: accent.withValues(alpha: 0.22)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SearchEntityTypeBadge(
                  label: viewData.entityLabel,
                  icon: SearchTaxonomyStyle.iconFor(type),
                  foregroundColor: accent,
                  backgroundColor: accent.withValues(alpha: 0.12),
                ),
                const SizedBox(height: AppSpacing.s16),
                CopyableText(
                  text: viewData.primaryTitle,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                  copiedStyle: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: accent,
                  ),
                ),
                const SizedBox(height: AppSpacing.s8),
                CopyableText(
                  text: viewData.scientificName,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: accent,
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w600,
                  ),
                  copiedStyle: theme.textTheme.titleMedium?.copyWith(
                    color: accent,
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (viewData.metrics.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.s16),
                  Wrap(
                    spacing: AppSpacing.s8,
                    runSpacing: AppSpacing.s8,
                    children: viewData.metrics
                        .map(
                          (metric) => _MetricChip(
                            label: metric.label,
                            count: metric.count,
                            accent: accent,
                          ),
                        )
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.s16),
          DetailSectionCard(
            child: Theme(
              data: theme.copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                initiallyExpanded: true,
                tilePadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s16,
                ),
                childrenPadding: const EdgeInsets.fromLTRB(
                  AppSpacing.s16,
                  0,
                  AppSpacing.s16,
                  AppSpacing.s12,
                ),
                leading: Icon(Icons.translate, color: accent, size: 20),
                title: Text(
                  context.loc.commonNames,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                children: viewData.commonNames.isEmpty
                    ? [
                        Text(
                          viewData.emptyCommonNamesLabel,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.5,
                            ),
                          ),
                        ),
                      ]
                    : viewData.commonNames
                          .map(
                            (name) =>
                                DetailBulletRow(label: name, copyable: true),
                          )
                          .toList(),
              ),
            ),
          ),
          if (viewData.classificationRows.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s12),
            _ClassificationSection(
              rows: viewData.classificationRows,
              accent: accent,
              emptyLabel: viewData.emptyClassificationLabel,
              onNavigate: onNavigate,
            ),
          ],
          if (viewData.attributes.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s12),
            DetailSectionCard(
              child: Padding(
                padding: AppSpacing.cardPaddingAll,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.sell_outlined, color: accent, size: 20),
                        AppSpacing.widthS8,
                        Text(
                          viewData.attributesTitle,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.s12),
                    ...viewData.attributes.map(
                      (attribute) => Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.s12),
                        child: DetailKeyValueRow(
                          label: attribute.label,
                          primary: attribute.value,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (!viewData.isReferenceBacked) ...[
            const SizedBox(height: AppSpacing.s12),
            DetailSectionCard(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.s16),
                child: Text(
                  viewData.referenceHint,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.s12),
          _ChildrenSection(
            future: childrenFuture,
            parentType: type,
            accent: accent,
            language: language,
            speciesListItemPresenter: speciesListItemPresenter,
            onNavigate: onNavigate,
            canNavigateToSpecies: canNavigateToSpecies,
          ),
        ],
      ),
    );
  }
}

class _ClassificationSection extends StatelessWidget {
  final List<TaxonomyClassificationRowViewModel> rows;
  final Color accent;
  final String emptyLabel;
  final void Function(SearchResult) onNavigate;

  const _ClassificationSection({
    required this.rows,
    required this.accent,
    required this.emptyLabel,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DetailSectionCard(
      child: Padding(
        padding: AppSpacing.cardPaddingAll,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.account_tree_outlined, color: accent, size: 20),
                AppSpacing.widthS8,
                Text(
                  context.loc.classification,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s12),
            if (rows.isEmpty)
              Text(
                emptyLabel,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              ...rows.map(
                (row) => _ClassificationRow(
                  row: row,
                  accent: accent,
                  onNavigate: onNavigate,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ClassificationRow extends StatelessWidget {
  final TaxonomyClassificationRowViewModel row;
  final Color accent;
  final void Function(SearchResult) onNavigate;

  const _ClassificationRow({
    required this.row,
    required this.accent,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isNavigable = row.id != null && row.entityType != null;

    final content = Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s12),
      child: Row(
        children: [
          Expanded(
            child: DetailKeyValueRow(
              label: row.label,
              primary: row.scientificName,
              secondary: row.commonName,
              italicPrimary: true,
              copyablePrimary: !isNavigable,
              copyableSecondary: !isNavigable,
            ),
          ),
          if (isNavigable)
            Icon(
              Icons.chevron_right_rounded,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              size: 20,
            ),
        ],
      ),
    );

    if (!isNavigable) return content;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => onNavigate(
        SearchResult(
          id: row.id!,
          name: row.scientificName,
          commonNames: const {},
          type: row.entityType!,
        ),
      ),
      child: content,
    );
  }
}

class _ChildrenSection extends StatelessWidget {
  final Future<List<SearchResult>> future;
  final SearchEntityType parentType;
  final Color accent;
  final Language language;
  final SpeciesListItemPresenter speciesListItemPresenter;
  final void Function(SearchResult) onNavigate;
  final bool canNavigateToSpecies;

  const _ChildrenSection({
    required this.future,
    required this.parentType,
    required this.accent,
    required this.language,
    required this.speciesListItemPresenter,
    required this.onNavigate,
    required this.canNavigateToSpecies,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FutureBuilder<List<SearchResult>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.s16),
              child: CircularProgressIndicator(),
            ),
          );
        }
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.s8),
            child: Text(
              'Fehler beim Laden: ${snapshot.error}',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          );
        }
        final children = snapshot.data ?? const [];
        if (children.isEmpty) return const SizedBox.shrink();

        final childType = children.first.type;
        final sectionTitle = _childrenSectionTitle(context, childType, children.length);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.s8),
              child: Row(
                children: [
                  Icon(
                    SearchTaxonomyStyle.iconFor(childType),
                    color: accent,
                    size: 18,
                  ),
                  AppSpacing.widthS8,
                  Text(
                    sectionTitle,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            ...children.map(
              (child) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.elementSpacing),
                child: _buildChildCard(context, child),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildChildCard(BuildContext context, SearchResult child) {
    final colorScheme = Theme.of(context).colorScheme;
    final item = speciesListItemPresenter.presentSearchResult(child, language);

    if (child.type == SearchEntityType.species) {
      final resolveThumbnailUrl = context
          .read<INaturalistService>()
          .fetchThumbnailUrl;
      return SpeciesListItem(
        item: item,
        onTap: canNavigateToSpecies ? () => onNavigate(child) : null,
        margin: EdgeInsets.zero,
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SearchResultThumbnail(
            scientificName: child.name,
            resolveThumbnailUrl: resolveThumbnailUrl,
            size: 64,
            accentColor: colorScheme.tertiary,
            backgroundColor: colorScheme.tertiaryContainer.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        trailing: canNavigateToSpecies
            ? Icon(
                Icons.chevron_right_rounded,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              )
            : null,
      );
    }

    return TaxonomySearchResultCard(
      primaryName: item.primaryName,
      scientificName: child.name,
      additionalNames: item.additionalNames,
      entityType: child.type,
      onTap: () => onNavigate(child),
    );
  }

  String _childrenSectionTitle(
    BuildContext context,
    SearchEntityType childType,
    int count,
  ) {
    final loc = context.loc;
    switch (childType) {
      case SearchEntityType.order:
        return '${loc.classificationOrder} ($count)';
      case SearchEntityType.family:
        return '${loc.classificationFamily} ($count)';
      case SearchEntityType.genus:
        return '${loc.classificationGenus} ($count)';
      case SearchEntityType.species:
        return '${loc.classificationSpecies} ($count)';
      case SearchEntityType.classType:
        return '${loc.classificationClass} ($count)';
    }
  }
}

class _MetricChip extends StatelessWidget {
  final String label;
  final int count;
  final Color accent;

  const _MetricChip({
    required this.label,
    required this.count,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s12,
        vertical: AppSpacing.s10,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$count',
            style: theme.textTheme.titleLarge?.copyWith(
              color: accent,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
