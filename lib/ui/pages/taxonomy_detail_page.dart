import 'package:discere/extensions/localization_extension.dart';
import 'package:discere/model/language.dart';
import 'package:discere/model/search/search_result.dart';
import 'package:discere/model/search/taxonomy_detail.dart';
import 'package:discere/persistence/taxonomy_repository.dart';
import 'package:discere/service/common/language_service.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:discere/theme/search_taxonomy_style.dart';
import 'package:discere/ui/components/detail_content_widgets.dart';
import 'package:discere/ui/components/search_result_card.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class TaxonomyDetailPage extends StatefulWidget {
  final SearchResult searchResult;

  const TaxonomyDetailPage({super.key, required this.searchResult});

  @override
  State<TaxonomyDetailPage> createState() => _TaxonomyDetailPageState();
}

class _TaxonomyDetailPageState extends State<TaxonomyDetailPage> {
  final TaxonomyRepository _repository = TaxonomyRepository();
  late Future<TaxonomyDetail> _futureDetail;

  @override
  void initState() {
    super.initState();
    _futureDetail = _repository.getDetail(widget.searchResult);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_entityLabel(context, widget.searchResult.type)),
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
              return _TaxonomyDetailContent(
                detail: snapshot.data!,
                language: languageService.getLanguage(),
              );
            },
          );
        },
      ),
    );
  }

  String _entityLabel(BuildContext context, SearchEntityType type) {
    switch (type) {
      case SearchEntityType.genus:
        return context.loc.classificationGenus;
      case SearchEntityType.family:
        return context.loc.classificationFamily;
      case SearchEntityType.order:
        return context.loc.classificationOrder;
      case SearchEntityType.classType:
        return context.loc.classificationClass;
      case SearchEntityType.species:
        return context.loc.classificationSpecies;
    }
  }
}

class _TaxonomyDetailContent extends StatelessWidget {
  final TaxonomyDetail detail;
  final Language language;

  const _TaxonomyDetailContent({required this.detail, required this.language});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = SearchTaxonomyStyle.colorFor(detail.result.type);
    final commonNames = _commonNames();

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
                  label: _entityLabel(context),
                  icon: SearchTaxonomyStyle.iconFor(detail.result.type),
                  foregroundColor: accent,
                  backgroundColor: accent.withValues(alpha: 0.12),
                ),
                const SizedBox(height: AppSpacing.s16),
                Text(
                  commonNames.isNotEmpty
                      ? commonNames.first
                      : detail.result.name,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppSpacing.s8),
                Text(
                  detail.result.name,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: accent,
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (detail.metrics.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.s16),
                  Wrap(
                    spacing: AppSpacing.s8,
                    runSpacing: AppSpacing.s8,
                    children: detail.metrics
                        .map(
                          (metric) => _MetricChip(
                            label: _metricLabel(context, metric.type),
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
                children: commonNames.isEmpty
                    ? [
                        Text(
                          context.loc.commonNotAvailable,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.5,
                            ),
                          ),
                        ),
                      ]
                    : commonNames
                          .map((name) => DetailBulletRow(label: name))
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
                  if (detail.classification.isEmpty)
                    Text(
                      detail.isReferenceBacked
                          ? context.loc.commonNoData
                          : context.loc.searchDetailReferenceHint,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    )
                  else
                    ...detail.classification.map(
                      (entry) => Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.s12),
                        child: DetailKeyValueRow(
                          label: _classificationLabel(context, entry.label),
                          primary: entry.scientificName,
                          secondary: entry.commonName,
                          italicPrimary: true,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (detail.attributes.isNotEmpty) ...[
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
                          'Attributes',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.s12),
                    ...detail.attributes.map(
                      (attribute) => Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.s12),
                        child: DetailKeyValueRow(
                          label: _attributeLabel(attribute.key),
                          primary: attribute.value,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (!detail.isReferenceBacked) ...[
            const SizedBox(height: AppSpacing.s12),
            DetailSectionCard(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.s16),
                child: Text(
                  context.loc.searchDetailReferenceHint,
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

  List<String> _commonNames() {
    final localized = _split(detail.commonNames[language]);
    if (localized.isNotEmpty) return localized;

    if (language != Language.en) {
      final english = _split(detail.commonNames[Language.en]);
      if (english.isNotEmpty) return english;
    }

    return const [];
  }

  List<String> _split(String? rawNames) {
    if (rawNames == null || rawNames.trim().isEmpty) {
      return const [];
    }

    final names = <String>[];
    final seen = <String>{};

    for (final rawName in rawNames.split(';')) {
      final trimmed = rawName.trim();
      if (trimmed.isEmpty) continue;
      final normalized = trimmed.toLowerCase();
      if (!seen.add(normalized)) continue;
      names.add(trimmed);
    }

    return names;
  }

  String _entityLabel(BuildContext context) {
    switch (detail.result.type) {
      case SearchEntityType.genus:
        return context.loc.classificationGenus;
      case SearchEntityType.family:
        return context.loc.classificationFamily;
      case SearchEntityType.order:
        return context.loc.classificationOrder;
      case SearchEntityType.classType:
        return context.loc.classificationClass;
      case SearchEntityType.species:
        return context.loc.classificationSpecies;
    }
  }

  String _classificationLabel(BuildContext context, TaxonomyRankLabel label) {
    switch (label) {
      case TaxonomyRankLabel.family:
        return context.loc.classificationFamily;
      case TaxonomyRankLabel.order:
        return context.loc.classificationOrder;
      case TaxonomyRankLabel.classType:
        return context.loc.classificationClass;
      case TaxonomyRankLabel.superClass:
        return context.loc.classificationSuperClass;
    }
  }

  String _attributeLabel(String key) {
    return key
        .split('_')
        .map(
          (part) => part.isEmpty
              ? part
              : '${part[0].toUpperCase()}${part.substring(1)}',
        )
        .join(' ');
  }

  String _metricLabel(BuildContext context, TaxonomyMetricType type) {
    switch (type) {
      case TaxonomyMetricType.species:
        return context.loc.searchDetailContainedSpecies;
      case TaxonomyMetricType.genera:
        return context.loc.searchDetailContainedGenera;
      case TaxonomyMetricType.families:
        return context.loc.searchDetailContainedFamilies;
      case TaxonomyMetricType.orders:
        return context.loc.searchDetailContainedOrders;
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
