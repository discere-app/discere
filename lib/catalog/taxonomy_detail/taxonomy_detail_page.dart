import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/catalog/model/search_result.dart';
import 'package:discere/catalog/model/taxonomy_detail.dart';
import 'package:discere/catalog/taxonomy_detail/taxonomy_detail_view_model.dart';
import 'package:discere/catalog/repository/locale_place_mapping_repository.dart';
import 'package:discere/catalog/repository/taxonomy_repository.dart';
import 'package:discere/catalog/taxonomy_detail/taxonomy_detail_presenter.dart';
import 'package:discere/catalog/taxonomy_detail/search_taxonomy_style.dart';
import 'package:discere/shared/service/language_service.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:discere/shared/ui/copyable_text.dart';
import 'package:discere/shared/ui/detail_content_widgets.dart';
import 'package:discere/catalog/search/search_result_card.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class TaxonomyDetailPage extends StatefulWidget {
  final SearchResult searchResult;

  const TaxonomyDetailPage({super.key, required this.searchResult});

  @override
  State<TaxonomyDetailPage> createState() => _TaxonomyDetailPageState();
}

class _TaxonomyDetailPageState extends State<TaxonomyDetailPage> {
  late final TaxonomyRepository _repository;
  final TaxonomyDetailPresenter _presenter = const TaxonomyDetailPresenter();
  late Future<TaxonomyDetail> _futureDetail;

  @override
  void initState() {
    super.initState();
    final localeRepo = context.read<LocalePlaceMappingRepository>();
    _repository = TaxonomyRepository(localeMapping: localeRepo.cached);
    _futureDetail = _repository.getDetail(widget.searchResult);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _presenter
              .present(
                TaxonomyDetail(
                  result: widget.searchResult,
                  commonNames: widget.searchResult.commonNames,
                  classification: const [],
                  metrics: const [],
                  isReferenceBacked: false,
                ),
                context.read<LanguageService>().getLanguage(),
                context.loc,
              )
              .pageTitle,
        ),
      ),
      body: FutureBuilder<TaxonomyDetail>(
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
              );
            },
          );
        },
      ),
    );
  }
}

class _TaxonomyDetailContent extends StatelessWidget {
  final TaxonomyDetailViewModel viewData;
  final SearchEntityType type;

  const _TaxonomyDetailContent({required this.viewData, required this.type});

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
          const SizedBox(height: AppSpacing.s12),
          DetailSectionCard(
            child: Padding(
              padding: AppSpacing.cardPaddingAll,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.account_tree_outlined,
                        color: accent,
                        size: 20,
                      ),
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
                  if (viewData.classificationRows.isEmpty)
                    Text(
                      viewData.emptyClassificationLabel,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    )
                  else
                    ...viewData.classificationRows.map(
                      (row) => Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.s12),
                        child: DetailKeyValueRow(
                          label: row.label,
                          primary: row.scientificName,
                          secondary: row.commonName,
                          italicPrimary: true,
                          copyablePrimary: true,
                          copyableSecondary: true,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
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
        ],
      ),
    );
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
