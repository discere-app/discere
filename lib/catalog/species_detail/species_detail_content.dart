import 'package:discere/catalog/common/taxon_identity/identity_header.dart';
import 'package:discere/catalog/model/search_result.dart';
import 'package:discere/catalog/model/species_with_local_images.dart';
import 'package:discere/catalog/species_detail/species_detail_presenter.dart';
import 'package:discere/catalog/species_detail/widgets/species_common_names_section.dart';
import 'package:discere/catalog/species_detail/widgets/species_conservation_status_section.dart';
import 'package:discere/catalog/species_detail/widgets/species_external_links.dart';
import 'package:discere/catalog/species_detail/widgets/species_facts_section.dart';
import 'package:discere/catalog/species_detail/widgets/species_media_carousel.dart';
import 'package:discere/catalog/species_detail/widgets/species_native_regions_section.dart';
import 'package:discere/catalog/species_detail/widgets/species_scientific_classification_section.dart';
import 'package:discere/catalog/species_detail/widgets/species_summary_section.dart';
import 'package:discere/shared/extensions/localization_extension.dart';
import 'package:discere/shared/model/language.dart';
import 'package:discere/shared/ui/detail_content_widgets.dart';
import 'package:discere/theme/app_spacing.dart';
import 'package:flutter/material.dart';

class SpeciesDetailContent extends StatelessWidget {
  final SpeciesWithLocalImages species;
  final Language language;
  final List<String> deckNames;
  final bool isRefreshingImages;
  final void Function(SearchResult)? onNavigateToTaxon;
  static const SpeciesDetailPresenter _presenter = SpeciesDetailPresenter();

  const SpeciesDetailContent({
    super.key,
    required this.species,
    required this.language,
    this.deckNames = const [],
    this.isRefreshingImages = false,
    this.onNavigateToTaxon,
  });

  @override
  Widget build(BuildContext context) {
    final viewData = _presenter.present(species.species, language, context.loc);
    final identity = viewData.identity;

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.s16,
            AppSpacing.s16,
            AppSpacing.s16,
            AppSpacing.s24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (viewData.isDeprecated) _DeprecatedBanner(species: species),
              IdentityHeader(identity: identity),
              const SizedBox(height: AppSpacing.s16),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 320),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  return FadeTransition(opacity: animation, child: child);
                },
                child: Stack(
                  key: ValueKey(
                    '${species.species.pictures.length}_${species.localPictures.length}',
                  ),
                  children: [
                    SpeciesMediaCarousel(
                      key: const Key('image'),
                      speciesWithLocalImages: species,
                      height: (constraints.maxWidth * 0.64).clamp(180.0, 260.0),
                      borderRadius: BorderRadius.circular(26),
                    ),
                    if (isRefreshingImages)
                      const Positioned(
                        top: AppSpacing.s12,
                        left: AppSpacing.s12,
                        child: _ImageRefreshIndicator(),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.s16),
              SpeciesCommonNamesSection(commonNames: identity.commonNames),
              const SizedBox(height: AppSpacing.s12),
              SpeciesScientificClassificationSection(
                rows: viewData.classificationRows,
                onNavigate: onNavigateToTaxon,
              ),
              const SizedBox(height: AppSpacing.s16),
              SpeciesFactsSection(section: viewData.factsSection),
              const SizedBox(height: AppSpacing.s16),
              SpeciesConservationStatusSection(speciesId: species.species.id),
              if (viewData.nativeRegionsSection != null) ...[
                const SizedBox(height: AppSpacing.s16),
                SpeciesNativeRegionsSection(
                  section: viewData.nativeRegionsSection!,
                ),
              ],
              if (deckNames.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.s16),
                _SpeciesDecksSection(deckNames: deckNames),
              ],
              const SizedBox(height: AppSpacing.s16),
              SpeciesSummarySection(
                speciesId: species.species.id,
                language: language,
              ),
              const SizedBox(height: AppSpacing.s20),
              SpeciesExternalLinks(species: species.species),
            ],
          ),
        );
      },
    );
  }
}

class _ImageRefreshIndicator extends StatelessWidget {
  const _ImageRefreshIndicator();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s12,
        vertical: AppSpacing.s8,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: AppSpacing.s8),
          Text(
            context.loc.speciesDetailLoadingImages,
            style: theme.textTheme.labelMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SpeciesDecksSection extends StatelessWidget {
  final List<String> deckNames;

  const _SpeciesDecksSection({required this.deckNames});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DetailSectionCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.loc.speciesDetailDecksTitle,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.s8),
            Wrap(
              spacing: AppSpacing.s16,
              runSpacing: AppSpacing.s8,
              children: deckNames
                  .map((name) => _DeckNameLabel(name: name))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeckNameLabel extends StatelessWidget {
  final String name;

  const _DeckNameLabel({required this.name});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.style_outlined,
          size: 18,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: AppSpacing.s8),
        Text(
          name,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _DeprecatedBanner extends StatelessWidget {
  final SpeciesWithLocalImages species;

  const _DeprecatedBanner({required this.species});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s16),
      child: Material(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s16,
            vertical: AppSpacing.s12,
          ),
          child: Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: theme.colorScheme.onErrorContainer,
              ),
              const SizedBox(width: AppSpacing.s8),
              Expanded(
                child: Text(
                  context.loc.speciesDeprecatedBanner,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
